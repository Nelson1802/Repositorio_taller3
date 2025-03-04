################################################################
# Problem Set 3: Script
# Authors: Yilmer Palacios, Betina Cortés, Lida Jimena Cárdenas,
# Nelson Fabián López
################################################################

# Loading Libraries ----
rm(list = ls()) 

# install.packages("pacman")
library("pacman")
p_load("tidyverse", "sf", "naniar", "tidymodels", "readxl", "psych","ranger","glmnet","naniar","tidyverse", "caret", "glmnet", "ggplot2","ggraph","gt")

#setwd("/Users/betinacortes/Desktop/Repositorio_taller3")
setwd("C:/Users/Yilmer Palacios/Desktop/Repositorios GitHub/Repositorio_taller3")


# Importing Dataset ----
# Removing City and operation type as they don't add information 
train <- read_csv("stores/Data_Kaggle/train.csv",
                  col_types = cols("price" = col_number())) |> 
  select(-c(city, operation_type))
test <- read_csv("stores/Data_Kaggle/test.csv",
                 col_types = cols("price" = col_number())) |> 
  select(-c(city, operation_type))

## Checking missing values ---- 
miss_var_summary(train)
miss_var_summary(test)

# Dados los altos porcentajes de missing values en las columnas surface_total,
# surface_covered, rooms y bathrooms en los conjuntos de datos de entrenamiento y prueba,
# no los utilizaremos como predictores. En su lugar, nos basaremos en gran medida en las 
# variables aumentadas.

train <- train |> select(-c(surface_total, surface_covered, rooms, bathrooms))
test <- test |> select(-c(surface_total, surface_covered, rooms, bathrooms))

# Augmenting Datasets ----

## a. Información sobre el crimen: Tasa de homicidios y hurto a residencias
## Fuente: Secretaría Distrital de Seguridad, Convivencia y Justicia
## https://scj.gov.co/es/oficina-oaiee/estadisticas-mapas

## Tabla con las tasas de homicidios y robos a residencias por UPZ
pop_crimen <- read_xlsx("stores/Crimen/pop_crimen_upz.xlsx") |> 
  pivot_longer(
    cols = pop_2018:hurtor_2021,
    names_to = c("var", "year"),
    names_pattern = "(.*)_(\\d*)"
  ) |> 
  pivot_wider(
    names_from = "var",
    values_from = "value"
  ) |> 
  mutate(
    tasa_hom = hom/pop *100000,
    tasa_hurtor = hurtor/pop * 100000,
    year = as.numeric(year)
  ) 

## Mapa de UPZ
## Fuente: IDECA - Catastro distrital

upz <- sf::st_read("stores/Geometries/UPZ/Upz.shp") |> 
  st_transform(4326) |> 
  mutate(CODIGO_UPZ = str_pad(CODIGO_UPZ, 3, pad = "0", side = "left"))

## Cargar las bases de datos train y test como geometry con el paquete sf

train_geo <- st_as_sf(train, coords = c("lon", "lat"), crs = 4326, remove = FALSE)
test_geo <- st_as_sf(test, coords = c("lon", "lat"), crs = 4326, remove = FALSE)

## UPZ para cada residencia

train_upz <- st_join(train_geo, upz, join = st_within)
test_upz <- st_join(test_geo, upz, join = st_within)

## Unir tasa de homicidios y robo a residencias por UPZ

train_crime <- train_upz |> 
  left_join(pop_crimen, by = c("CODIGO_UPZ" = "Código UPZ",
                               "year" = "year")) |> 
  select(-c(OBJECTID, ZONA_ESTAC, DECRETO_PO, ACTO_ADMIN, AREA_HECTA,
            SHAPE_Leng, SHAPE_Area, pop, hom, hurtor, `Nombre UPZ`))

test_crime <- test_upz |> 
  left_join(pop_crimen, by = c("CODIGO_UPZ" = "Código UPZ",
                               "year" = "year")) |> 
  select(-c(OBJECTID, ZONA_ESTAC, DECRETO_PO, ACTO_ADMIN, AREA_HECTA,
            SHAPE_Leng, SHAPE_Area, pop, hom, hurtor, `Nombre UPZ`))

## b. Información sobre servicios/amenidades cercanas: número de colegios, ips (hospitales) y parques en 250m
## Fuente: IDECA - Catastro distrital

## Colegios
schools <- sf::st_read("stores/Geometries/Colegios/Colegios_2022_03.shp")

## Hospitales
ips <- sf::st_read("stores/Geometries/ips/ips.shp")

## Parques
parks <- sf::st_read("stores/Geometries/parques/parques.shp")

## Contar colegios, parques y hospitales dentro de cada UPZ

## Colegios en UPZ
schools_upz <- st_join(schools, upz |> st_transform(st_crs(schools)),
                       join = st_within) |> 
  st_drop_geometry() |> 
  count(CODIGO_UPZ, name = "n_schools") |> 
  drop_na()

## Parques en UPZ
parks_upz <- st_join(parks, upz |> st_transform(st_crs(parks)),
                     join = st_within) |> 
  st_drop_geometry() |> 
  count(CODIGO_UPZ, name = "n_parks") |> 
  drop_na()

## Hospitales in UPZ
ips_upz <- st_join(ips, upz |> st_transform(st_crs(ips)),
                   join = st_within) |> 
  st_drop_geometry() |> 
  count(CODIGO_UPZ, name = "n_ips") |> 
  drop_na()

## Agregar la información sobre servicios/amenidades cercanas a la base de datos anterior

train_amenities <- train_crime |> 
  left_join(schools_upz, by = "CODIGO_UPZ") |> 
  left_join(parks_upz, by = "CODIGO_UPZ") |> 
  left_join(ips_upz, by = "CODIGO_UPZ") |> 
  replace_na(list(n_schools = 0, n_parks = 0, n_ips = 0))

test_amenities <- test_crime |> 
  left_join(schools_upz, by = "CODIGO_UPZ") |> 
  left_join(parks_upz, by = "CODIGO_UPZ") |> 
  left_join(ips_upz, by = "CODIGO_UPZ") |> 
  replace_na(list(n_schools = 0, n_parks = 0, n_ips = 0))

## c. Características de la vivienda: Parqueaderos, depósitos, patios y terrazas

## Para esta sección, se realiza una búsqueda dentro de las descripciones de 
## cada vivienda

add_facilities <- function(dataset) {
  dataset |> 
    mutate(tiene_terraza = str_detect(description, ".*[Tt]erraza.*"),
           tiene_patio = str_detect(description, ".*[Pp]atio.*"),
           tiene_parqueadero = str_detect(description, ".*[Pp]arquead.*"),
           tiene_deposito = str_detect(description, ".*[Dd]ep[oó]sito.*"))
}

train_facilities <- train_amenities |> add_facilities()

test_facilities <- test_amenities |> add_facilities()

## Se verifican los missing values en las bases de datos train_final y test-final
naniar::miss_var_summary(train_facilities)
naniar::miss_var_summary(test_facilities)

##  Cleanup final de las bases de datos
train_final <- train_facilities |> 
  replace_na(list(tiene_terraza = F,
                  tiene_patio = F,
                  tiene_parqueadero = F,
                  tiene_deposito = F)) |> 
  select(-c(title, description, CODIGO_UPZ, NOMBRE,
            `Código localidad`, `Nombre localidad`)) |> 
  replace_na(list(tasa_hom = mean(train_facilities$tasa_hom, na.rm = TRUE),
                  tasa_hurtor = mean(train_facilities$tasa_hurtor, na.rm = TRUE))) |> 
  st_drop_geometry()

naniar::miss_var_summary(train_final)


test_final <- test_facilities |> 
  replace_na(list(tiene_terraza = F,
                  tiene_patio = F,
                  tiene_parqueadero = F,
                  tiene_deposito = F)) |> 
  select(-c(title, description, CODIGO_UPZ, NOMBRE,
            `Código localidad`, `Nombre localidad`, price)) |> 
  replace_na(list(tasa_hom = mean(train_facilities$tasa_hom, na.rm = TRUE),
                  tasa_hurtor = mean(train_facilities$tasa_hurtor, na.rm = TRUE))) |> 
  st_drop_geometry()

naniar::miss_var_summary(test_final)

## Se exportan las bases de datos finales

write_csv(train_final, "stores/train_final.csv")
write_csv(test_final, "stores/test_final.csv")

rm(train_facilities, test_facilities)

## teniendo las bases finales hacemos un resumen de las bases de dato de trabajo

###### Summary tables ----

describeBy(train_final |> select(bedrooms, tasa_hom, tasa_hurtor,
                                 n_schools, n_parks, n_ips,
                                 tiene_terraza, tiene_patio,
                                 tiene_parqueadero, tiene_deposito,
                                 property_type),
           group = "property_type", fast = TRUE)

list_functions <- list(
  mean = ~mean(.x, na.rm = TRUE),
  min = ~min(.x, na.rm = TRUE),
  max = ~max(.x, na.rm = TRUE),
  sd = ~sd(.x, na.rm = TRUE) 
)

## Resumen para las variables numericas
table_1 <- train_final |> 
  select(-c(year, month)) |> 
  summarise(across(
    where(is.numeric),
    list_functions,
    .names = "{.col}__{.fn}"
  )) |> 
  pivot_longer(
    price__mean:n_ips__sd, names_to = "var", values_to = "value"
  ) |> 
  separate(var, sep = "__", into = c("Variable", "medida")) |> 
  pivot_wider(
    id_cols = Variable, names_from = medida, values_from = value
  )

table_2 <- test_final |> 
  select(-c(year, month)) |> 
  summarise(across(
    where(is.numeric),
    list_functions,
    .names = "{.col}__{.fn}"
  )) |> 
  pivot_longer(
    bedrooms__mean:n_ips__sd, names_to = "var", values_to = "value"
  ) |> 
  separate(var, sep = "__", into = c("Variable", "medida")) |> 
  pivot_wider(
    id_cols = Variable, names_from = medida, values_from = value
  ) 

table_3 <- table_1 |> 
  left_join(table_2, by = "Variable", suffix = c("_train", "_test")) |> 
  mutate(
    Variable = case_when(
      Variable == "price" ~ "Precio",
      Variable == "bedrooms" ~ "Cuartos",
      Variable == "lat" ~ "Latidud",
      Variable == "lon" ~ "Longitud",
      Variable == "tasa_hom" ~ "Tasa de Homicidio",
      Variable == "tasa_hurtor" ~ "Tasa de hurto a residencias",
      Variable == "n_schools" ~ "Número de colegios",
      Variable == "n_parks" ~ "Número de parques",
      Variable == "n_ips" ~ "Número de hospitales")
  )

numeric_output <- table_3 |> 
  gt() |> 
  fmt_number(
    columns = mean_train:sd_test,
    decimals = 2
  ) |> 
  cols_label(
    mean_train = "Mean",
    min_train = "Min",
    max_train = "Max",
    sd_train = "SD",
    mean_test = "Mean",
    min_test = "Min",
    max_test = "Max",
    sd_test = "SD",
  ) |> 
  cols_width(
    ends_with("train") ~ px(130),
    ends_with("test") ~ px(130)
  ) |> 
  tab_header(
    title = md("**Estadísticas de resumen**"),
    subtitle = " Variables numéricas"
  ) |> 
  tab_spanner(
    label = "Entrenamiento",
    columns = c(mean_train, min_train, max_train, sd_train)
  ) |> 
  tab_spanner(
    label = "Prueba",
    columns = c(mean_test, min_test, max_test, sd_test)
  ) |> 
  tab_source_note(
    source_note = "Nota: No se incluye información sobre las variables de habitaciones, area total, cubierta y baños porque no se usaron en el entrenamiento."
  )

gtsave(numeric_output, "resumen_numericas.html")

## Resumen para las variables dicótomas

table_4 <- train_final |> 
  summarise(across(
    where(is.logical),
    mean
  )) |> 
  pivot_longer(
    tiene_terraza:tiene_deposito, names_to = "Variable", values_to = "value"
  )

table_5 <- test_final |> 
  summarise(across(
    where(is.logical),
    mean
  )) |> 
  pivot_longer(
    tiene_terraza:tiene_deposito, names_to = "Variable", values_to = "value"
  )

table_6 <- table_4 |> 
  left_join(table_5, by = "Variable", suffix = c("_train", "_test")) |> 
  mutate(
    Variable = case_when(
      Variable == "tiene_terraza" ~ "Tiene terraza",
      Variable == "tiene_patio" ~ "Tiene patio",
      Variable == "tiene_parqueadero" ~ "Tiene parqueadero",
      Variable == "tiene_deposito" ~ "Tiene depósito")
  )

logical_output <- table_6 |> 
  gt() |> 
  fmt_number(
    columns = value_train:value_test,
    decimals = 2
  ) |> 
  cols_label(
    value_train = "Entrenamiento",
    value_test = "Prueba"
  ) |> 
  cols_width(
    ends_with("train") ~ px(150),
    ends_with("test") ~ px(150),
    Variable ~ px(200)
  ) |> 
  tab_header(
    title = md("**Estadísticas de resumen**"),
    subtitle = "Variables lógicas"
  ) |> 
  tab_spanner(
    label = "Proporción",
    columns = c(value_train, value_test)
  ) |> 
  tab_source_note(
    source_note = "Nota: No se incluye información sobre las variables de habitaciones, area total, cubierta y baños porque no se usaron en el entrenamiento."
  )

gtsave(logical_output, "resumen_logicas.html")

### hacemos los Mapas

ggplot() +
  geom_sf(data = upz) +
  geom_sf(data = train_geo, alpha = 0.075, size = 0.2, color = "darkblue") +
  labs(
    title = "Distribución de los inmuebles\nen venta sobre las\nUPZ de Bogotá",
    subtitle = "Conjunto de entrenamiento"
  ) +
  theme_void() +
  theme(
    plot.title = element_text(hjust = 0.5, size = 8, face = "bold"),
    plot.subtitle = element_text(hjust = 0.5, size = 6.5),
    plot.background = element_rect(fill = "white", color = NA)
  )

ggsave("viviendas_entrenamiento.png", width = 700, height = 1000, unit = "px")

ggplot() +
  geom_sf(data = upz) +
  geom_sf(data = test_geo, alpha = 0.075, size = 0.2, color = "darkgreen") +
  labs(
    title = "Distribución de los inmuebles\nen venta sobre las\nUPZ de Bogotá",
    subtitle = "Conjunto de prueba"
  ) +
  theme_void() +
  theme(
    plot.title = element_text(hjust = 0.5, size = 8, face = "bold"),
    plot.subtitle = element_text(hjust = 0.5, size = 6.5),
    plot.background = element_rect(fill = "white", color = NA)
  )

ggsave("viviendas_prueba.png", width = 700, height = 1000, unit = "px")


##########################################################
############ Predicciones del precio   ###################
##########################################################

## Modelo N1. Regresión lineal simple
lin_reg_fit <- linear_reg() |> 
  set_engine("lm") |> 
  fit(price ~ year + month + bedrooms + property_type + lat + lon + tasa_hom + tasa_hurtor + n_schools + n_parks + n_ips + tiene_terraza + tiene_parqueadero + tiene_patio + tiene_deposito,
      data = train_final)

lin_reg_predict <- predict(lin_reg_fit, new_data = test_final)

lin_reg_output <- test_final |> 
  select(property_id) |> 
  bind_cols(lin_reg_predict) |> 
  rename(price = .pred)

lin_reg_output

write_csv(lin_reg_output, "stores/Predictions/lin_reg.csv")

## Regresión Lineal regularizada

## Lasso 

lasso_reg_fit <- linear_reg(penalty = 0.001, mixture = 1) |> 
  set_engine("glmnet") |> 
  fit(price ~ year + month + bedrooms + property_type + lat + lon + tasa_hom + tasa_hurtor + n_schools + n_parks + n_ips + tiene_terraza + tiene_parqueadero + tiene_patio + tiene_deposito,
      data = train_final)

lasso_reg_predict <- predict(lasso_reg_fit, new_data = test_final)

lasso_reg_output <- test_final |> 
  select(property_id) |> 
  bind_cols(lasso_reg_predict) |> 
  rename(price = .pred)

write_csv(lasso_reg_output, "stores/Predictions/lasso_reg.csv")

## Ridge

ridge_reg_fit <- linear_reg(penalty = 0.001, mixture = 0) |> 
  set_engine("glmnet") |> 
  fit(price ~ year + month + bedrooms + property_type + lat + lon + tasa_hom + tasa_hurtor + n_schools + n_parks + n_ips + tiene_terraza + tiene_parqueadero + tiene_patio + tiene_deposito,
      data = train_final)

ridge_reg_predict <- predict(ridge_reg_fit, new_data = test_final)

ridge_reg_output <- test_final |> 
  select(property_id) |> 
  bind_cols(lin_reg_predict) |> 
  rename(price = .pred)

write_csv(ridge_reg_output, "stores/Predictions/ridge_reg.csv")

## Regresión con Random Forest

random_forest_fit <- rand_forest(mode = "regression") |> 
  set_engine("ranger") |> 
  fit_xy(
    x = train_final[, c("year", "month", "bedrooms", "property_type",
                        "lat", "lon", "tasa_hom", "tasa_hurtor", 
                        "n_schools", "n_parks", "n_ips", 
                        "tiene_terraza", "tiene_parqueadero",
                        "tiene_patio", "tiene_deposito")],
    y = train_final$price
  )

random_forest_predict <- predict(random_forest_fit, new_data = test_final)

random_forest_output <- test_final |> 
  select(property_id) |> 
  bind_cols(random_forest_predict) |> 
  rename(price = .pred)

write_csv(random_forest_output, "stores/Predictions/random_forest.csv")
  
