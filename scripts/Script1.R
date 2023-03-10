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

# Importing Dataset ----
# Removing City and operation type as they dont add information 
train <- read_csv("Data/Kaggle/train.csv",
                  col_types = cols("price" = col_number())) |> 
  select(-c(city, operation_type))
test <- read_csv("Data/Kaggle/test.csv",
                 col_types = cols("price" = col_number())) |> 
  select(-c(city, operation_type))
