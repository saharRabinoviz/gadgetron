#include "cgOperatorNonCartesianSense.h"

#include "hoNDArray_fileio.h"

#include <cublas_v2.h>

int cgOperatorNonCartesianSense::mult_M(cuNDArray<float2>* in, 
				     cuNDArray<float2>* out, 
				     bool accumulate)
{
  if (!(in->dimensions_equal(dimensions_)) ||
      !(out->dimensions_equal(dimensions_out_)) ) {

    std::cerr << "cgOperatorCartesianSense::mult_M dimensions mismatch" << std::endl;

    return -1;
  }

  cuNDArray<float2> tmp;
  std::vector<unsigned int> full_dimensions = dimensions_;
  full_dimensions.push_back(coils_);

  if (!tmp.create(full_dimensions)) {
    std::cerr << "cgOperatorCartesianSense::mult_M unable to allocate temp array" << std::endl;
    return -1;    
  }

  if (mult_csm(in,&tmp) < 0) {
    std::cerr << "cgOperatorCartesianSense::mult_M : Unable to multiply with coil sensitivities" << std::endl;
    return -1;
  }

  std::cout << "Writing temp" << std::endl;
  hoNDArray<float2> tmp_host = tmp.to_host();
  write_nd_array<float2>(tmp_host,"tmp_csm_mult.cplx");

  std::vector<unsigned int> out_dims = out->get_dimensions();
  std::vector<unsigned int> tmp_dims = tmp.get_dimensions();

  if (coils_ == 1) {
    out->squeeze();
    tmp.squeeze();
  }

  //Do the NFFT
  if (!plan_.compute( out, &tmp, weights_, NFFT_plan<uint2, float2, float, float2>::NFFT_FORWARDS )) {
    std::cerr << "cgOperatorNonCartesianSense::mult_M : failed during NFFT" << std::endl;
    return -1;
  }

  if (coils_ == 1) {
    out->reshape(out_dims);
  }

  return 0;
}

int cgOperatorNonCartesianSense::mult_MH(cuNDArray<float2>* in, cuNDArray<float2>* out, bool accumulate)
{

  if (!(out->dimensions_equal(dimensions_)) ||
      !(in->dimensions_equal(dimensions_out_)) ) {
    std::cerr << "cgOperatorCartesianSense::mult_MH dimensions mismatch" << std::endl;
    return -1;
  }

  std::vector<unsigned int> tmp_dimensions = dimensions_;
  tmp_dimensions.push_back(coils_);

  cuNDArray<float2> tmp;
  if (!tmp.create(tmp_dimensions)) {
    std::cerr << "cgOperatorCartesianSense::mult_MH: Unable to create temp storage" << std::endl;
    return -1;
  }

  clear(&tmp);

  if (!weights_) {
    std::cerr << "cgOperatorNonCartesianSense::mult_MH : gridding weights are zero, aborting" << std::endl;
    return -1;
  }

  std::vector<unsigned int> tmp_dims_in = in->get_dimensions();
  if (coils_ == 1) {
    in->squeeze();
    tmp.squeeze();
  }

  //Do the NFFT
  if (!plan_.compute( in, &tmp, weights_, NFFT_plan<uint2, float2, float, float2>::NFFT_BACKWARDS )) {
    std::cerr << "cgOperatorNonCartesianSense::mult_MH : failed during NFFT" << std::endl;
    return -1;
  }

  if (coils_ == 1) {
    in->reshape(tmp_dims_in);
  }

  if (!accumulate) clear(out);
  

  if (mult_csm_conj_sum(&tmp,out) < 0) {
    std::cerr << "cgOperatorCartesianSense::mult_MH: Unable to multiply with conjugate of sensitivity maps and sum" << std::endl;
    return -1;
 
  }

  return 0;
}


int cgOperatorNonCartesianSense::set_trajectories(cuNDArray<float2>* trajectory) {
  if (trajectory) {
    trajectory_ = trajectory;
    samples_ = trajectory->get_number_of_elements();
    dimensions_out_.clear();
    dimensions_out_.push_back(samples_);
    dimensions_out_.push_back(coils_);
  
    uint2 matrix_size;
    matrix_size.x = dimensions_[0];
    matrix_size.y = dimensions_[1];
    
    uint2 matrix_size_os;
    matrix_size_os.x = ((dimensions_[0]*2.0)/32)*32;
    matrix_size_os.y = ((dimensions_[1]*2.0)/32)*32;
    
    uint2 fixed_dims;
    fixed_dims.x = 0;
    fixed_dims.y = 0;
    
    if (!plan_.setup(matrix_size,matrix_size_os,fixed_dims, 4)) {
      std::cerr << "cgOperatorNonCartesianSense: failed to setup plan" << std::endl;
      return -1;
    }

    if (!plan_.preprocess(trajectory_,false)) {
      std::cerr << "cgOperatorNonCartesianSense: failed to run preprocess" << std::endl;
      return -1;
    }

  } else {
    return -2;
  }
  
  return 0;
}
