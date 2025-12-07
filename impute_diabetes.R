#!/usr/bin/env Rscript
# impute_diabetes.R
# Random forest imputation on Diabetes dataset

# ---- 0. Setup ----
setwd("/scratch/reb515/Diabeetus/final_project_ml")

library(tidyverse)
library(randomForest)
library(caret)

set.seed(123)

# ---- 1. Load data ----
# Assumes Diabetes.csv is in the working directory
Diabetes <- read_csv("Diabetes.csv")

# Drop rows with missing outcome
Diabetes <- Diabetes %>% filter(!is.na(Diabetes_binary))

# ---- 2. Stratified train/test split by Diabetes_binary ----
train_index <- createDataPartition(Diabetes$Diabetes_binary, p = 0.8, list = FALSE)

train <- Diabetes[train_index, ]
test  <- Diabetes[-train_index, ]

# ---- 3. Encode variables on TRAIN ----

# Binary 0/1 variables to treat as factors
binary_vars <- c(
  "HighBP","HighChol","CholCheck","Smoker","Stroke","HeartDiseaseorAttack",
  "PhysActivity","Fruits","Veggies","HvyAlcoholConsump","AnyHealthcare",
  "NoDocbcCost","DiffWalk","Sex","Diabetes_binary"
)

# Ordinal / scale-like variables to treat as ordered factors
scale_like <- c(
  "GenHlth",      # 1–5 self-rated health
  "PhysHlth",     # days (buckets)
  "MentHlth",
  "Age",          # age bucket
  "Education",
  "Income"
)

train <- train %>%
  mutate(
    across(any_of(binary_vars), ~ factor(.x)),
    across(any_of(scale_like),  ~ factor(.x, ordered = TRUE))
  )

# ---- 4. Fast random-forest imputation function ----

impute_with_rf_fast <- function(train_df,
                                var_name,
                                ntree = 80,
                                sample_frac = 0.4) {
  
  y <- train_df[[var_name]]
  miss_idx <- which(is.na(y))
  
  # No missing values
  if (length(miss_idx) == 0L) {
    message("No missing values for ", var_name)
    return(train_df)
  }
  
  obs_idx <- which(!is.na(y))
  
  # Not enough data to fit a forest
  if (length(obs_idx) < 20L) {
    message("Too few observed rows for ", var_name, " — skipping")
    return(train_df)
  }
  
  # Downsample training subset for speed
  set.seed(123)
  if (length(obs_idx) > 10000) {
    n_sample   <- floor(length(obs_idx) * sample_frac)
    obs_sample <- sample(obs_idx, n_sample)
  } else {
    obs_sample <- obs_idx
  }
  
  predictors <- setdiff(names(train_df), var_name)
  form <- as.formula(paste(var_name, "~", paste(predictors, collapse = " + ")))
  
  is_numeric <- is.numeric(y)
  
  message(
    "Imputing ", var_name,
    ifelse(is_numeric, " (regression)", " (classification)"),
    " on ", length(obs_sample), " rows"
  )
  
  rf_fit <- randomForest(
    formula   = form,
    data      = train_df[obs_sample, , drop = FALSE],
    ntree     = ntree,
    na.action = na.omit
  )
  
  pred <- predict(rf_fit, newdata = train_df[miss_idx, , drop = FALSE])
  
  # Keep factor levels consistent
  if (is.factor(y)) {
    pred <- factor(pred, levels = levels(y))
  }
  
  train_df[[var_name]][miss_idx] <- pred
  return(train_df)
}

# ---- 5. Find variables with missingness and impute ----

vars_with_na <- train %>%
  select(-Diabetes_binary) %>%         # don't ever impute the outcome
  summarise(across(everything(), ~ any(is.na(.)))) %>%
  pivot_longer(everything(), names_to = "var", values_to = "has_na") %>%
  filter(has_na) %>%
  pull(var)

print(vars_with_na)

train_imp <- train

for (v in vars_with_na) {
  train_imp <- impute_with_rf_fast(train_imp, v)
}

# ---- 6. Save imputed training set ----

cat("About to write train_imputed.csv in:\n")
print(getwd())

write.csv(train_imp, "train_imputed.csv", row.names = FALSE)
cat("Finished writing train_imputed.csv\n")

