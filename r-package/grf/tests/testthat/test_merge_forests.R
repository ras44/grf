library(grf)

test_that("Merged regression forest attributes are sensible", {
  # Train regression forests
  n <- 50
  p <- 2
  X <- matrix(rnorm(n * p), n, p)
  Y <- X[, 1] * rnorm(n)
  W <- X[, 2] > 0
  r.forest1 <- regression_forest(X, Y, compute.oob.predictions = FALSE, num.trees = 10)
  r.forest2 <- regression_forest(X, Y, compute.oob.predictions = FALSE, num.trees = 10)

  # Join the forests together.
  big.rf <- merge_forests(list(r.forest1, r.forest2))

  # Result is also a regression_forest of the same class
  expect_true(is(big.rf, "grf"))
  expect_equal(r.forest1[["_num_trees"]] + r.forest2[["_num_trees"]], big.rf[["_num_trees"]])
  expect_equal(class(r.forest1), class(big.rf))
})

test_that("Merged causal forest attributes are sensible", {
  # Train causal forests
  n <- 50
  p <- 2
  X <- matrix(rnorm(n * p), n, p)
  Y <- X[, 1] * rnorm(n)
  W <- X[, 2] > 0
  c.forest1 <- causal_forest(X, Y, W, compute.oob.predictions = FALSE, num.trees = 10)
  c.forest2 <- causal_forest(X, Y, W, compute.oob.predictions = FALSE, num.trees = 10)

  # Join the forests together.
  big.rf <- merge_forests(list(c.forest1, c.forest2))

  # Result is also a causal forest of the same class
  expect_true(big.rf[["_num_trees"]] == (c.forest1[["_num_trees"]] + c.forest2[["_num_trees"]]))
  expect_true(is(big.rf, "grf"))
  expect_equal(class(c.forest1), class(big.rf))

  expect_equal(c.forest1$Y.hat, big.rf$Y.hat)
  expect_equal(c.forest1$W.hat, big.rf$W.hat)
})


test_that("Merged causal forests give reasonable predictions", {
  n <- 50
  p <- 2
  X <- matrix(rnorm(n * p), n, p)
  Y <- X[, 1] * rnorm(n)
  W <- X[, 2] > 0

  # Train a causal forest.
  c.forest1 <- causal_forest(X, Y, W, num.trees = 100)

  # Train another forest and merge it into the first.
  c.forest2 <- causal_forest(X, Y, W, num.trees = 100)
  big.rf <- merge_forests(list(c.forest1, c.forest2))

  preds <- predict(c.forest1)
  excess.error <- mean(preds$excess.error)
  error <- mean(preds$debiased.error) + excess.error

  big.preds <- predict(big.rf)
  big.excess.error <- mean(big.preds$excess.error)
  big.error <- mean(big.preds$debiased.error) + big.excess.error

  expect_lt(big.error, error)
  expect_lt(big.excess.error, excess.error)
})

test_that("Incompatible forests are not mergeable", {
  # Train causal forests
  n <- 50
  p <- 2
  X <- matrix(rnorm(n * p), n, p)
  Y <- X[, 1] * rnorm(n)
  W <- X[, 2] > 0

  c.forest1 <- causal_forest(X, Y, W,
    compute.oob.predictions = FALSE, num.trees = 10,
    ci.group.size = 3
  )
  c.forest2 <- causal_forest(X, Y, W,
    compute.oob.predictions = FALSE, num.trees = 10,
    ci.group.size = 4
  )
  r.forest1 <- regression_forest(X, Y, ci.group.size = 3)

  #  Empty input
  expect_error(merge_forests(list()))
  # Incompatible classes
  expect_error(merge_forests(list(c.forest1, r.forest1)))
  # Incompatible ci.group.size
  expect_error(merge_forests(list(c.forest1, c.forest2)))
})
