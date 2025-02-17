#' Predict Watershed
#' 
#' Train Watershed model on training data and predict Watershed posterior probabilities 
#' (using Watershed parameters optimized in training) on all gene-individual in a much larger prediction data set. 
#'
#' @param training_input String. The Watershed input file containing instances used to train the model.
#'   Either a file path or a URL. For required format, see details of [evaluate_watershed()].  
#' @param prediction_input String. The Watershed input file containing instances to predict on.
#'   Either a file path or a URL. For required format, see details of [evaluate_watershed()].  
#' @param number_dimensions Integer representing the number of outlier types. 
#'   Sometimes referred to as \code{E} in our documentation.  
#' @param model_name String identifier corresponding to the model to use. 
#'   Options are "RIVER", "Watershed_exact", and "Watershed_approximate"
#' @param dirichlet_prior_parameter Float parameter defining Dirichlet distribution that acts 
#'   as a prior a Phi (the model parameters defining \code{E|Z})
#' @param l2_prior_parameter Float defining the L2 (gaussian) distribution that acts 
#'   as a prior on the parameters defining the conditional random field \code{P(Z|G)}. 
#'   If set to NULL, Watershed will run a grid search on held-out data to select an 
#'   optimal L2 prior. Default: 0.1
#' @param output_prefix String corresponding to the prefix of all output files generated by this function
#' @param binary_pvalue_threshold Float. Absolute p-value threshold used to create 
#'   binary outliers used for Genomic Annotation Model. Default: 0.1
#' @param lambda_costs Numeric vector of length 3. If \code{l2_prior_parameter} is NULL, 
#'   perform grid search over the following values of lambda to determine optimal lambda.
#'   Default: \code{c(.1, .01, 1e-3)}
#' @param nfolds Integer. If \code{l2_prior_parameter} is NULL, Number of folds 
#'   to be used in K-fold cross validation for Genomic annotation model. Default: 5
#' @param vi_step_size Float. Parameter used for Variational Optimization. 
#'   Only applies if \code{model_name == "Watershed_approximate"}. Default: 0.8
#' @param vi_threshold Float. Parameter used for Variational Optimization. 
#'   Only applies if \code{model_name == "Watershed_approximate"}. Default: 1e-8
#'
#' @export
#'
#' @seealso [evaluate_watershed()]
#' 
#' @examples
#' # Note for convenience, the training file is the same as the prediction file. 
#' # This does not necessarily have to be the case.
#' input = paste0("https://raw.githubusercontent.com/BennyStrobes/Watershed/",
#'      "master/example_data/watershed_example_data.txt")
#' 
#' # For all examples, use example data that has 3 E outlier p-value columns, 
#' # which corresponds to number_of_dimensions = 3
#' 
#' \dontrun{
#' # Run using Watershed approximate inference
#' predict_watershed(training_input = input, 
#'                   prediction_input = input,
#'                   model_name = "Watershed_approximate", 
#'                   number_dimensions = 3,
#'                   output_prefix = "watershed_approximate_n3")
#' 
#' # Run using Watershed exact inference
#' predict_watershed(training_input = input, 
#'                   prediction_input = input,
#'                   model_name = "Watershed_exact", 
#'                   number_dimensions = 3,
#'                   output_prefix = "watershed_exact_n3")
#' 
#' # Run using RIVER
#' predict_watershed(training_input = input, 
#'                   prediction_input = input,
#'                   model_name = "RIVER", 
#'                   number_dimensions = 3,
#'                   output_prefix = "river_n3")
#' }
#' 
#' @details 
#' "Watershed_exact" is Watershed where parameters are optimized via exact inference 
#' (tractable and recommended when \code{E} is small. A general rule of thumb is if \code{E} is 
#' less than equal to 4, exact inference should be used). "Watershed_approximate" 
#' is Watershed where parameters are optimized using approximate inference. 
#' This approach is tractable when \code{E} is large.
#' 
#' This function saves a tab-separated file to \code{${output_prefix}posterior_probability.txt}.
#' Each line of this file corresponds to an instance (a line) in the prediction input file 
#' \code{$prediction_input}. The "sample_names" column provides the identifier for the gene-individual 
#' pair corresponding to the given line. There is an additional column for each of the 
#' \code{E} outliers, where the column corresponding to outlier \code{e} represents the 
#' Watershed marginal posterior probability for outlier \code{e}.
predict_watershed <- function(training_input,
                              prediction_input,
                              number_dimensions = 1,
                              model_name = "Watershed_exact",
                              dirichlet_prior_parameter = 10,
                              l2_prior_parameter = 0.1,
                              output_prefix = "watershed",
                              binary_pvalue_threshold = 0.1,
                              lambda_costs = c(.1, .01, 1e-3),
                              nfolds = 5, 
                              vi_step_size = 0.8,
                              vi_threshold = 1e-8){

  # process args
  training_input_file <- training_input
  prediction_input_file <- prediction_input
  number_of_dimensions <- number_dimensions
  model_name <- tolower(model_name)
  pseudoc <- dirichlet_prior_parameter
  lambda_init <- l2_prior_parameter
  output_stem <- output_prefix
  binary_pvalue_threshold <- binary_pvalue_threshold
  
  # Change model to RIVER if there is only 1 dimension.
  if(!model_name %in% c("river","watershed_exact","watershed_approximate")){
    stop("Model name must be one of 'RIVER', 'Watershed_exact', 'Watershed_approximate'.")
  }
  
  # Change model to RIVER if there is only 1 dimension.
  if (number_of_dimensions == 1 & model_name != "river"){
    warning("Only RIVER can be run on data with 1 dimension.\n Changing model to RIVER.")
    model_name <- "river"
  }
  
  #######################################
  ## Train Watershed model on training data
  #######################################
  watershed_object <- learn_watershed_model_parameters_from_training_data(training_input_file, 
                                                                          number_of_dimensions, 
                                                                          model_name, 
                                                                          pseudoc, 
                                                                          lambda_init, 
                                                                          binary_pvalue_threshold, 
                                                                          lambda_costs, 
                                                                          nfolds, 
                                                                          vi_step_size, 
                                                                          vi_threshold)
  
  #######################################
  ## Save trained object as .rds file
  #######################################
  saveRDS(watershed_object, paste0(output_stem, "_prediction_object.rds"))
  
  
  #######################################
  ## Estimate Watershed posteriors using trained watershed_object
  #######################################
  posteriors <- predict_watershed_posteriors(watershed_object, prediction_input_file, number_of_dimensions)
  
  
  #######################################
  ## Save Watershed posterior predictions to outputfile
  #######################################
  output_file <- paste0(output_stem, "_posterior_probability.txt")
  write.table(posteriors,file=output_file, sep="\t", quote=FALSE, row.names=FALSE)
}


#######################################
## Train Watershed model on training data
#######################################
learn_watershed_model_parameters_from_training_data <- function(training_input_file, 
                                                                number_of_dimensions, 
                                                                model_name, 
                                                                pseudoc, 
                                                                lambda_init, 
                                                                binary_pvalue_threshold, 
                                                                lambda_costs, 
                                                                nfolds, 
                                                                vi_step_size, 
                                                                vi_threshold) {
	########################
	## Load in data
	########################
	data_input <- load_watershed_data(training_input_file, number_of_dimensions, .01, binary_pvalue_threshold)
	# Parse data_input for relevent data
	feat_all <- data_input$feat
	discrete_outliers_all <- data_input$outliers_discrete
	binary_outliers_all <- data_input$outliers_binary

	#######################################
	## Standardize Genomic Annotations (features)
	#######################################
	mean_feat <- apply(feat_all, 2, mean)
	sd_feat <- apply(feat_all, 2, sd)
 	feat_all <- scale(feat_all, center=mean_feat, scale=sd_feat)

  	#######################################
	## Fit Genomic Annotation Model (GAM)
	#######################################
	gam_data <- logistic_regression_genomic_annotation_model_cv(feat_all, 
	                                                            binary_outliers_all, 
	                                                            nfolds, 
	                                                            lambda_costs, 
	                                                            lambda_init)
	# Report optimal lambda learned from cross-validation data (if applicable)
	if (is.na(lambda_init)) {
		cat(paste0(nfolds,"-fold cross validation on GAM yielded optimal lambda of ", gam_data$lambda, "\n"))
	}

	#######################################
	### Initialize phi using GAM
	#######################################
	# Compute GAM Predictions on data via function in  CPP file ("independent_crf_exact_updates.cpp")
	gam_posterior_obj <- update_independent_marginal_probabilities_exact_inference_cpp(feat_all, 
	                                                                                   binary_outliers_all, 
	                                                                                   gam_data$gam_parameters$theta_singleton, 
	                                                                                   gam_data$gam_parameters$theta_pair, 
	                                                                                   gam_data$gam_parameters$theta, 
	                                                                                   matrix(0,2,2), 
	                                                                                   matrix(0,2,2), 
	                                                                                   number_of_dimensions, 
	                                                                                   choose(number_of_dimensions, 2), 
	                                                                                   FALSE)
	gam_posteriors <- gam_posterior_obj$probability
	# Initialize Phi using GAM posteriors
	# ie. Compute MAP estimates of the coefficients defined by P(outlier_status| FR)
	phi_init <- map_phi_initialization(discrete_outliers_all, gam_posteriors, number_of_dimensions, pseudoc)

	#######################################
	### Fit Watershed Model
	#######################################
	watershed_model <- train_watershed_model(feat_all, 
	                                         discrete_outliers_all, 
	                                         phi_init, 
	                                         gam_data$gam_parameters$theta_pair, 
	                                         gam_data$gam_parameters$theta_singleton, 
	                                         gam_data$gam_parameters$theta, 
	                                         pseudoc, 
	                                         gam_data$lambda, 
	                                         number_of_dimensions, 
	                                         model_name, 
	                                         vi_step_size, 
	                                         vi_threshold)

	return(list(mean_feat=mean_feat,sd_feat=sd_feat, model_params=watershed_model, gam_model_params=gam_data))
}


predict_watershed_posteriors <- function(watershed_object, prediction_input_file, number_dimensions) {
	########################
	## Load in prediction data
	########################
	prediction_data_input <- load_watershed_data(prediction_input_file, number_dimensions, .01, .01)
	# Parse data_input for relevent data
	predictions_feat <- prediction_data_input$feat
	predictions_discretized_outliers <- prediction_data_input$outliers_discrete
	# Scale prediction features (according to mean and standard deviation from training data)
	predictions_feat <- scale(predictions_feat, center=watershed_object$mean_feat, scale=watershed_object$sd_feat) 


	########################
	## Inference to compute Watershed posterior probabilities
	########################
	watershed_info <- update_marginal_posterior_probabilities(predictions_feat, 
	                                                          predictions_discretized_outliers, 
	                                                          watershed_object$model_params)
	watershed_posteriors <- watershed_info$probability  # Marginal posteriors

	########################
	# Add row names and column names to posterior predictions matrix
	########################
	posterior_mat <- cbind(rownames(predictions_feat), watershed_posteriors)
	colnames(posterior_mat) = c("sample_names", paste0("Watershed_posterior_outlier_signal_", 1:number_dimensions))

	return(posterior_mat)
}
