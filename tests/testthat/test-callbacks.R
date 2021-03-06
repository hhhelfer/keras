
context("callbacks")

source("utils.R")


# generate dummy training data
data <- matrix(rexp(1000*784), nrow = 1000, ncol = 784)
labels <- matrix(round(runif(1000*10, min = 0, max = 9)), nrow = 1000, ncol = 10)

# genereate dummy input data
input <- matrix(rexp(10*784), nrow = 10, ncol = 784)

define_compile_and_fit <- function(callbacks) {
  model <- define_and_compile_model()
  fit(model, data, labels, callbacks = callbacks, epochs = 1)
}

test_callback <- function(name, callback, h5py = FALSE, required_version = NULL) {

  test_succeeds(required_version = required_version,
                paste0("callback_", name, " is called back"),  {
    if (h5py && !have_h5py())
      skip(paste(name, "test requires h5py package"))
    define_compile_and_fit(callbacks = list(callback))   
  })
}

test_callback("progbar_logger", callback_progbar_logger())
test_callback("model_checkpoint", callback_model_checkpoint(tempfile(fileext = ".h5")), h5py = TRUE)
test_callback("learning_rate_scheduler", callback_learning_rate_scheduler(schedule = function (index, ...) {
  0.1
}))
if (is_keras_available() && is_backend("tensorflow"))
  test_callback("tensorboard", callback_tensorboard(log_dir = "./tb_logs"))

test_callback("terminate_on_naan", callback_terminate_on_naan(), required_version = "2.0.5")

test_callback("reduce_lr_on_plateau", callback_reduce_lr_on_plateau(monitor = "loss"))

test_callback("csv_logger", callback_csv_logger(tempfile(fileext = ".csv")))
test_callback("lambd", callback_lambda(
  on_epoch_begin = function(epoch, logs) {
    cat("Epoch Begin\n")
  },
  on_epoch_end = function(epoch, logs) {
    cat("Epoch End\n")
  }
))

test_succeeds("lambda callbacks other args", {
  
  x <- layer_input(shape = 1)
  y <- layer_dense(x, units = 1)
  model <- keras_model(x, y)
  model %>% compile(optimizer = "adam", loss = "mae")
  
  warns <- capture_warnings(
    clb <- callback_lambda(
      on_epoch_begin = function(epoch, logs) {
        cat("Epoch Begin")
      },
      on_epoch_end = function(epoch, logs) {
        cat("Epoch End")
      },
      on_predict_begin = function(epoch, logs) {
        cat("Prediction Begin")
      },
      on_test_begin = function(epoch, logs) {
        cat("Test Begin")
      }
    )
  )
  
  if (get_keras_implementation() == "tensorflow" && 
      tensorflow::tf_version() >= "2.0") {
    expect_equal(length(warns), 0)
  } else {
    expect_equal(length(warns), 2)
  }
  
  warns <- capture_warnings(
    out <- capture_output(
      pred <- predict(model, matrix(1:10, ncol = 1), callbacks = list(clb))   
    )
  )
  
  if (get_keras_implementation() == "tensorflow" && 
      tensorflow::tf_version() >= "2.0") {
    expect_equal(length(warns), 0)
    expect_equal(out, "Prediction Begin")
  } else {
    expect_equal(length(warns), 1)
    expect_equal(out, "")
  }
  
  warns <- capture_warnings(
    out <- capture_output(
      pred <- evaluate(model, matrix(1:10, ncol = 1), y = 1:10, 
                       callbacks = list(clb))   
    )
  )
  
  if (get_keras_implementation() == "tensorflow" && 
      tensorflow::tf_version() >= "2.0") {
    expect_equal(length(warns), 0)
    expect_equal(out, "Test Begin")
  } else {
    expect_equal(length(warns), 1)
    expect_equal(out, "")
  }
  
})


test_succeeds("custom callbacks", {
  
  CustomCallback <- R6::R6Class("CustomCallback",
    inherit = KerasCallback,
    public = list(
      on_train_begin = function(logs) {
        print("TRAIN BEGIN\n")
      },
      on_train_end = function(logs) {
        print("TRAIN END\n")
      }
    )
  )
  
  LossHistory <- R6::R6Class("LossHistory",
    inherit = KerasCallback,
    public = list(
      losses = NULL,
     
      on_batch_end = function(batch, logs = list()) {
        self$losses <- c(self$losses, logs[["loss"]])
      }
      
    ))
  
  cc <- CustomCallback$new()
  lh <- LossHistory$new()

  define_compile_and_fit(callbacks = list(cc, lh))
  
  expect_is(lh$losses, "numeric")
  
})


expect_warns_and_out <- function(warns, out) {
  if (get_keras_implementation() == "tensorflow" && 
      tensorflow::tf_version() >= "2.0") {
    expect_equal(out, c("PREDICT BEGINPREDICT END")) 
    expect_equal(warns, character())
  } else {
    expect_equal(out, "")
    expect_true(warns != "")
  }
}

test_succeeds("on predict/evaluation callbacks", {
  
  if (tensorflow::tf_version() >= "2.1")
    skip("TODO: R based generators are not working with TF >= 2.1")
  
  CustomCallback <- R6::R6Class(
    "CustomCallback",
    inherit = KerasCallback,
    public = list(
      on_predict_begin = function(logs) {
        cat("PREDICT BEGIN")
      },
      on_predict_end = function(logs) {
        cat("PREDICT END")
      },
      on_test_begin = function(logs) {
        cat("PREDICT BEGIN")
      },
      on_test_end = function(logs) {
        cat("PREDICT END")
      }
    )
  )
  
  input <- layer_input(shape = 1)
  output <- layer_dense(input, 1)
  model <- keras_model(input, output)
  model %>% compile(optimizer = "adam", loss = "mae")
  
  cc <- CustomCallback$new()
 
  # test for prediction
  warns <- capture_warnings(
    out <- capture_output(
      pred <- predict(model, x = matrix(1:10, ncol = 1), callbacks = cc)
    )  
  )
  expect_warns_and_out(warns, out)
  
  gen <- function() {
    list(matrix(1:10, ncol = 1))
  }
  
  warns <- capture_warnings(
    out <- capture_output(
      pred <- predict_generator(model, gen, callbacks = cc, steps = 1)  
    )
  )
  expect_warns_and_out(warns, out)
  
  # tests for evaluation
  warns <- capture_warnings(
    out <- capture_output(
      ev <- evaluate(model, x = matrix(1:10, ncol = 1), y = 1:10, callbacks = cc)
    )
  )
  expect_warns_and_out(warns, out)
  
  gen <- function() {
    list(matrix(1:10, ncol = 1), 1:10)
  }
  
  warns <- capture_warnings(
    out <- capture_output(
      ev <- evaluate_generator(model, gen, callbacks = cc, steps = 1)
    )
  )
  expect_warns_and_out(warns, out)
  
})

test_succeeds("warnings for new callback moment", {
  
  CustomCallback <- R6::R6Class(
    "CustomCallback",
    inherit = KerasCallback,
    public = list(
      on_predict_begin = function(logs) {
        cat("PREDICT BEGIN")
      },
      on_predict_end = function(logs) {
        cat("PREDICT END")
      },
      on_test_begin = function(logs) {
        cat("PREDICT BEGIN")
      },
      on_test_end = function(logs) {
        cat("PREDICT END")
      }
    )
  )
  
  cc <- CustomCallback$new()
  
  input <- layer_input(shape = 1)
  output <- layer_dense(input, 1)
  model <- keras_model(input, output)
  model %>% compile(optimizer = "adam", loss = "mae")
  
  warns <- capture_warnings(
    model %>% 
      fit(x = matrix(1:10, ncol = 1), y = 1:10, callbacks = list(cc), 
          verbose = 0, epochs = 2)  
  )
  
  if (get_keras_implementation() == "tensorflow" && tensorflow::tf_version() < "2.0")
    expect_equal(length(warns), 4)
  else
    expect_equal(length(warns), 0)
    
})
