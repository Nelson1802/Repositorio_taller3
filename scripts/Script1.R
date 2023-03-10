################################################################
# Problem Set 3: Script
# Authors: Yilmer Palacios, Betina Cortés, Lida Jimena Cárdenas,
# Nelson Fabián López
################################################################

# Loading Libraries ----
rm(list = ls()) 

# install.packages("pacman")
library("pacman")
p_load("tidyverse", "sf", "naniar", "tidymodels", "readxl", "psych","ranger","glmnet","naniar")

#setwd("/Users/betinacortes/Desktop/Repositorio_taller3")
#setwd("C:/Users/Yilmer Palacios/Desktop/Repositorios GitHub/Repositorio_taller3")


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
## Fuente: Catastro Distrital

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


