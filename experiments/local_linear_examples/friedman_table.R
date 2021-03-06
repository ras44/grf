library(grf)
library(glmnet)
library(BART) 
library(xgboost) 

set.seed(1234)

ff = function(x){
  return(10*sin(pi*x[1]*x[2]) + 20*((x[3] - 0.5)**2) + 10*x[4] + 5*x[5])
}

boosting.cv = function(dtrain, Y){
  
  # cross-validate on a reasonable grid 
  etas = seq(0, 0.3, by = 0.1)
  nrounds = c(50, 100, 500, 1000)
  max_depth = seq(2, 8, by = 2)
  
  args.cv = expand.grid(e = etas, n = nrounds, d = max_depth)
  results = t(apply(args.cv, MARGIN = 1, FUN = function(arguments){
    model.xgb = xgboost(dtrain, nrounds = arguments[2], 
                        params = list(objective = "reg:linear"),
                        eval_metric = "rmse",
                        eta = arguments[1], 
                        max_depth = arguments[3])
    xgb.preds = predict(model.xgb, newdata = dtrain)
    mean((xgb.preds - Y)**2)
  }))
  best.index = which.min(results)
  return(args.cv[best.index,])
}

simulation.run = function(n, p, sigma, num.reps = 100, ntest = 2000, num.trees = 2000){
  errors = replicate(num.reps, {
    X = matrix(runif(n*p,0,1), nrow = n)
    Y = apply(X, MARGIN = 1, FUN = ff) + sigma * rnorm(n)
    
    X.test = matrix(runif(ntest*p, 0, 1), nrow = ntest)
    truth = apply(X.test, MARGIN = 1, FUN = ff)
    
    # use stepwise regression to select linear correction variables 
    data = data.frame(cbind(X,Y))
    colnames(data) = c(paste("V",1:p,sep=""), "Y")
    baseModel <- lm(Y ~ 1, data = data)
    upper <- as.formula(paste("Y~", paste(paste("V",1:p,sep=""), collapse = "+")))
    mod <- step(baseModel, scope = list(upper = upper, lower = baseModel), trace = 0)
    names.selected = names(mod$coefficients)[2:length(names(mod$coefficients))]
    selected = sapply(names.selected, function(item){
      num = substring(item,2)
      as.numeric(num)
    })
    selected = data.frame(selected)$selected
    
    forest = regression_forest(X, Y, honesty = TRUE, tune.parameters = TRUE, num.trees = num.trees)
    
    llf.stepwise.preds = predict(forest, X.test, linear.correction.variables = selected, tune.lambda = TRUE)$predictions 
    llf.stepwise.mse = mean((llf.stepwise.preds - truth)**2)
    
    # use lasso to select linear correction variables
    lasso.mod = cv.glmnet(X, Y, alpha = 1)
    lasso.coef = predict(lasso.mod, type = "nonzero")
    if(!is.null(dim(lasso.coef))){
      selected = lasso.coef[,1]
    } else {
      selected = 1:ncol(X)
    }
    llf.lasso.preds = predict(forest, X.test, linear.correction.variables = selected, tune.lambda = TRUE)$predictions 
    llf.lasso.mse = mean((llf.lasso.preds - truth)**2)
    
    # LLF oracle: with correct linear correction variables 
    llf.oracle.preds = predict(forest, X.test, linear.correction.variables = 1:5, tune.lambda = TRUE)$predictions 
    llf.oracle = mean((llf.oracle.preds - truth)**2)
    
    rf.preds = predict(forest, X.test, tune.parameters = TRUE)$predictions 
    rf.mse = mean((rf.preds - truth)**2)
    
    forest.adapt = regression_forest(X, Y, honesty = FALSE, tune.parameters = TRUE, num.trees = num.trees)
    rf.adapt.preds = predict(forest.adapt, X.test)$predictions 
    rf.adapt.mse = mean((rf.adapt.preds - truth)**2)
    
    inds = sample(n, size=n/2, replace = FALSE)
    lasso.mod = cv.glmnet(X[inds,], Y[inds], alpha = 1)
    lasso.preds = predict(lasso.mod, newx = X[-inds,], s ="lambda.min")
    lasso.resids = as.numeric(Y[-inds] - lasso.preds)
    
    rf = regression_forest(X[-inds,], lasso.resids, honesty = TRUE)
    lasso.rf.preds = predict(rf, newdata = X.test)$predictions + predict(lasso.mod, newx = X.test, s = "lambda.min")
    lasso.rf.mse = mean((lasso.rf.preds-truth)**2)
    
    bart.mod = wbart(X, Y, X.test, nskip = 5, ndpost = 5)
    bart.preds = bart.mod$yhat.test.mean
    bart.mse = mean((bart.preds-truth)**2)
    
    dtrain = xgb.DMatrix(X, label = Y)
    cv.variables = as.numeric(boosting.cv(dtrain, Y))
    eta = cv.variables[1]
    nrounds = cv.variables[2]
    max_depth = cv.variables[3]
    
    model.xgb = xgboost(dtrain, nrounds = nrounds, params = list(objective = "reg:linear"),
                        eval_metric = "rmse", eta = eta, max_depth = max_depth)
    xgb.preds = predict(model.xgb, newdata = X.test)
    xg.mse = mean((xgb.preds - truth)**2)
    
    c(llf.stepwise.mse, llf.oracle, rf.mse, rf.adapt.mse, lasso.rf.mse, bart.mse, xg.mse, llf.lasso.mse)
  })
  c("LLF-stepwise" = mean(errors[1,]),
    "LLF-lasso" = mean(errors[8,]),
    "LLF-oracle"= mean(errors[2,]),
    "RF-honest" = mean(errors[3,]),
    "RF-adapt" = mean(errors[4,]),
    "Lasso-RF" = mean(errors[5,]),
    "BART" = mean(errors[6,]),
    "XGBoost" = mean(errors[7,]))
}
 
ps = seq(10, 50, by = 10)
ns = c(1000, 5000)
sigmas = c(5, 10, 20)
num.reps = 50

args = expand.grid(n = ns, p = ps, sigma = sigmas)
full.results = t(apply(args, MARGIN = 1, FUN = function(arguments){
  print(arguments)
  mses = simulation.run(arguments[1], arguments[2], arguments[3], num.reps = num.reps)
  sqrt(mses)
}))
full.results = cbind(args, round(full.results, 3))
full.results

write.csv(full.results, "friedman_table.csv", row.names = FALSE)
