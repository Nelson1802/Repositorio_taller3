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
train <- read_csv("stores/train.csv",
                  col_types = cols("price" = col_number())) |> 
  select(-c(city, operation_type))
test <- read_csv("stores/test.csv",
                 col_types = cols("price" = col_number())) |> 
  select(-c(city, operation_type))

## Checking missing values ---- 
miss_var_summary(train)
miss_var_summary(test)

# Given the high percentages of missing values in the columns surface_total,
# surface covered, rooms and bathrooms in both the train and test data sets,
# we wont use them as predictors. Instead, we will rely strongly  on the 
# augmented variables.
