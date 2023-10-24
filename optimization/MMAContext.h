#pragma once

#ifdef __CUDACC__
#include "culib2/gpuVector.cuh"
// using namespace gv2;

namespace homo {
	class MMAContext {
	public:
		gv2::gVector<double> xvar;
		gv2::gVector<double> xmin, xmax, xold1, xold2;
		gv2::gVector<double> low, upp;
		gv2::gVector<double> df0dx;
		gv2::gVector<double> gval;
		gv2::gVector<double> dgdx; size_t gpitch;
		gv2::gVector<double> acd;
		// gVector<double> xvar;
		// gVector<double> xmin, xmax, xold1, xold2;
		// gVector<double> low, upp;
		// gVector<double> df0dx;
		// gVector<double> gval;
		// gVector<double> dgdx; size_t gpitch;
		// gVector<double> acd;
};
}
#else


#endif

