# Load necessary libraries
library(tidyverse)
library(broom)
library(ggplot2)
library(caret)
install.packages("glmnet")
library(glmnet)

# Load the data
byssinosis_data <- read.csv("Byssinosis.csv")
byssinosis_data <- byssinosis_data %>%
  filter(Byssinosis > 0 | Non.Byssinosis > 0)
head(byssinosis_data)

# Inspect the data structure
str(byssinosis_data)

# Calculate total workers and byssinosis rate
byssinosis_data <- byssinosis_data %>%
  mutate(Total_Workers = Byssinosis + Non.Byssinosis,
         Byssinosis_Rate = Byssinosis / Total_Workers)

# Exploratory Data Analysis (EDA)
# Summary of byssinosis rate by workplace dustiness
data_summary_workspace <- byssinosis_data %>%
  group_by(Workspace) %>%
  summarise(Average_Byssinosis_Rate = mean(Byssinosis_Rate, na.rm = TRUE),
            Total_Workers = sum(Total_Workers))

print(data_summary_workspace)

# Summary of byssinosis rate by employment duration
data_summary_employment <- byssinosis_data %>%
  group_by(Employment) %>%
  summarise(Average_Byssinosis_Rate = mean(Byssinosis_Rate, na.rm = TRUE),
            Total_Workers = sum(Total_Workers))

print(data_summary_employment)

# Summary of byssinosis rate by smoking status
data_summary_smoking <- byssinosis_data %>%
  group_by(Smoking) %>%
  summarise(Average_Byssinosis_Rate = mean(Byssinosis_Rate, na.rm = TRUE),
            Total_Workers = sum(Total_Workers))

print(data_summary_smoking)

# Summary of byssinosis rate by sex
data_summary_sex <- byssinosis_data %>%
  group_by(Sex) %>%
  summarise(Average_Byssinosis_Rate = mean(Byssinosis_Rate, na.rm = TRUE),
            Total_Workers = sum(Total_Workers))

print(data_summary_sex)

# Summary of byssinosis rate by race
data_summary_race <- byssinosis_data %>%
  group_by(Race) %>%
  summarise(Average_Byssinosis_Rate = mean(Byssinosis_Rate, na.rm = TRUE),
            Total_Workers = sum(Total_Workers))

print(data_summary_race)

# Visualize byssinosis rate by workplace dustiness
plot1 <- ggplot(byssinosis_data, aes(x = factor(Workspace), y = Byssinosis_Rate)) +
  geom_boxplot(fill = "skyblue", alpha = 0.7) +
  labs(title = "Byssinosis Rate by Workplace Dustiness",
       x = "Workplace Dustiness (1=Most Dusty, 3=Least Dusty)",
       y = "Byssinosis Rate") +
  theme(plot.title = element_text(hjust = 0.5))

print(plot1)



# Split data into training and testing sets
set.seed(123) # For reproducibility
train_index <- createDataPartition(byssinosis_data$Byssinosis_Rate, p = 0.8, list = FALSE)
train_data <- byssinosis_data[train_index, ]
test_data <- byssinosis_data[-train_index, ]

# Fit a logistic regression model with forward stepwise selection, considering interaction terms
# Start with a null model and a full model including interaction terms
null_model <- glm(Byssinosis_Rate ~ 1, 
                  data = train_data, 
                  weights = Total_Workers,
                  family = binomial(link = "logit"))

full_model <- glm(Byssinosis_Rate ~ factor(Workspace) * Employment * Smoking * Sex * Race,
                  data = train_data, 
                  weights = Total_Workers,
                  family = binomial(link = "logit"))

# Perform forward stepwise selection
stepwise_model_1 <- step(null_model, 
                       scope = list(lower = null_model, upper = full_model), 
                       direction = "forward", 
                       k = 2,
                       trace = 0)# AIC penalty term

stepwise_model_2 <- step(null_model, 
                       scope = list(lower = null_model, upper = full_model), 
                       direction = "forward", 
                       k = log(nrow(train_data)),
                       trace = 0) # BIC penalty term

# Summarize the selected model
summary(stepwise_model_1)
summary(stepwise_model_2)


# Test the model on the testing set
test_data <- test_data %>%
  mutate(Predicted_Probability_1 = predict(stepwise_model_1, newdata = test_data, type = "response"))
test_data <- test_data %>%
  mutate(Predicted_Probability_2 = predict(stepwise_model_2, newdata = test_data, type = "response"))


# Evaluate model performance using RMSE
rmse_value_1 <- sqrt(mean((test_data$Byssinosis_Rate - test_data$Predicted_Probability_1)^2))
cat("\nRMSE for model selected by AIC: ", rmse_value_1, "\n")
rmse_value_2 <- sqrt(mean((test_data$Byssinosis_Rate - test_data$Predicted_Probability_2)^2))
cat("\nRMSE for model selected by BIC: ", rmse_value_2, "\n")

# Prepare data for OLS and Lasso
x_train <- model.matrix(Byssinosis_Rate ~ factor(Workspace) * Employment * Smoking * Sex * Race, data = train_data)[, -1]
y_train <- train_data$Byssinosis_Rate
x_test <- model.matrix(Byssinosis_Rate ~ factor(Workspace) * Employment * Smoking * Sex * Race, data = test_data)[, -1]
y_test <- test_data$Byssinosis_Rate

# Fit an OLS model with forward stepwise selection using AIC
null_model_ols <- lm(Byssinosis_Rate ~ 1, data = train_data)
full_model_ols <- lm(Byssinosis_Rate ~ factor(Workspace) * Employment * Smoking * Sex * Race, data = train_data)

# Perform forward stepwise selection using AIC
stepwise_model_ols <- step(null_model_ols, 
                           scope = list(lower = null_model_ols, upper = full_model_ols), 
                           direction = "forward")

# Summarize the selected model
ols_model_summary <- summary(stepwise_model_ols)
print(ols_model_summary)

# Test the selected OLS model on the testing set
ols_predictions_stepwise <- predict(stepwise_model_ols, newdata = test_data)
ols_rmse_stepwise <- sqrt(mean((test_data$Byssinosis_Rate - ols_predictions_stepwise)^2))
cat("\nStepwise OLS RMSE: ", ols_rmse_stepwise, "\n")

# Lasso Regression
set.seed(123)
lasso_model <- cv.glmnet(x_train, y_train, alpha = 1, family = "gaussian")
lasso_best_lambda <- lasso_model$lambda.min
cat("\nBest Lambda for Lasso: ", lasso_best_lambda, "\n")

# Fit Lasso model with the best lambda
final_lasso_model <- glmnet(x_train, y_train, alpha = 1, lambda = lasso_best_lambda)
lasso_predictions <- predict(final_lasso_model, s = lasso_best_lambda, newx = x_test)
lasso_rmse <- sqrt(mean((y_test - lasso_predictions)^2))
cat("\nLasso RMSE: ", lasso_rmse, "\n")

# Choose stepwise_model_1 as our final model
# Visualize odds ratios for predictors in the final model
tidy_model <- tidy(stepwise_model_1)

plot2 <- tidy_model %>%
  mutate(Odds_Ratio = exp(estimate),
         Lower_CI = exp(estimate - 1.96 * std.error),
         Upper_CI = exp(estimate + 1.96 * std.error)) %>%
  filter(term != "(Intercept)") %>%
  ggplot(aes(x = reorder(term, Odds_Ratio), y = Odds_Ratio)) +
  geom_point(size = 3) +
  geom_errorbar(aes(ymin = Lower_CI, ymax = Upper_CI), width = 0.2) +
  coord_flip() +
  labs(title = "Odds Ratios of Predictors for Byssinosis",
       x = "Predictors",
       y = "Odds Ratio") +
  theme(plot.title = element_text(hjust = 0.5))

print(plot2)

# Conclusion
cat("\nConclusion:\n")
cat("Workplace dustiness appears to significantly contribute to the chance of byssinosis, with higher dust levels associated with increased byssinosis rates.\n")
cat("Forward stepwise selection identified key predictors and interaction terms for byssinosis.\n")

data.frame(Model = c("logistic by AIC", "logistic by BIC", "Stepwise OLS", "LASSO"), RMSE = c(0.05312408, 0.07693695, 0.06611631, 0.05747427))
