#pragma once

#ifndef __TEMPLATE_MATRIX_H
#define __TEMPLATE_MATRIX_H

#include "Eigen/Eigen"
#include "gpu_manager_t.h"

typedef double Scalar;

constexpr double default_poisson_ratio = 0.3;
constexpr double default_youngs_modulus = 1e6;


void initTemplateMatrix(Scalar element_len, gpu_manager_t& gm, Scalar ymodu = default_youngs_modulus, Scalar ps_ratio = default_poisson_ratio);

void initTemplateMatrix_cloak1(Scalar element_len, gpu_manager_t& gm, Scalar ymodu = default_youngs_modulus, Scalar ps_ratio = default_poisson_ratio);

void initTemplateMatrix_cloak2(Scalar element_len, gpu_manager_t& gm, Scalar ymodu = default_youngs_modulus, Scalar ps_ratio = default_poisson_ratio);

const Eigen::Matrix<Scalar, 24, 24>& getTemplateMatrix(void);

const Scalar* getTemplateMatrixElements(void);

const Eigen::Matrix<Scalar, 24, 24>& getTemplateMatrix11(void);

const Scalar* getTemplateMatrixElements11(void);

const Eigen::Matrix<Scalar, 24, 24>& getTemplateMatrix12(void);

const Scalar* getTemplateMatrixElements12(void);

const Eigen::Matrix<Scalar, 24, 24>& getTemplateMatrix44(void);

const Scalar* getTemplateMatrixElements44(void);

Scalar* getDeviceTemplateMatrix(void);


#endif

