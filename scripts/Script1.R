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

setwd("/Users/betinacortes/Desktop/Repositorio_taller3")

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


