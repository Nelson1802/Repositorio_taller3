################################################################
# Problem Set 3: Script
# Authors: Yilmer Palacios, Betina Cortés, Lida Jimena Cárdenas,
# Nelson Fabián López
################################################################

# Loading Libraries ----
rm(list = ls()) 

# install.packages("pacman")
library("pacman")
p_load("tidyverse", "sf", "naniar", "tidymodels", "readxl", "psych","ranger","glmnet")

setwd("/Users/betinacortes/Desktop/Repositorio_taller3")

# Importing Dataset ----
# Removing City and operation type as they dont add information 
train <- read_csv("/Users/betinacortes/Desktop/Repositorio_taller3/stores/train.csv",
                  col_types = cols("price" = col_number())) |> 
  select(-c(city, operation_type))
test <- read_csv("/Users/betinacortes/Desktop/Repositorio_taller3/stores/test.csv",
                 col_types = cols("price" = col_number())) |> 
  select(-c(city, operation_type))
