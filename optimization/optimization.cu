#include "optimization.h"
#include "cuda_runtime.h"
//#include "device_atomic_functions.hpp"
#include "lib.cuh"
#include "Grid.h"
#include "gpuVector.h"
#include <vector>
#include "templateMatrix.h"
//#include "gpuVector.h"

extern  __constant__  double gTemplateMatrix[24][24];
extern  __constant__  double gTemplateMatrix11[24][24];
extern  __constant__  double gTemplateMatrix12[24][24];
extern  __constant__  double gTemplateMatrix44[24][24];
extern  __constant__ int* gV2E[8];
extern  __constant__ int* gV2Vfine[27];
extern  __constant__ int* gV2Vcoarse[8];
extern  __constant__ int* gV2V[27];
extern  __constant__ int* gVfine2Vfine[27];
extern  __constant__ int* gV2VfineC[64];// vertex to fine grid element center 
extern  __constant__ int* gVfine2Efine[8];
extern  __constant__ int* gVfine2Effine[8];
extern  __constant__ float power_penalty[1];
extern  __constant__ double* gU[3];
extern  __constant__ double* gF[3];
extern  __constant__ double* gR[3];
// extern __constant__ double* glambda[3];
// extern __constant__ double* gFforlambda[3];  //=-2(U-U0)
// extern __constant__ double* gRforlambda[3];
extern  __constant__ double* gUworst[3];
extern  __constant__ double* gFworst[3];
extern  __constant__ double* gRfine[3];
extern  __constant__ double* gUcoarse[3];
extern  __constant__ int gGS_num[8];
extern  __constant__ int gmode[1];
extern  __constant__ int* gVflag[1];
extern  __constant__ int* gEflag[1];
extern  __constant__ int gLayerid[1];
extern  __constant__ int gDEBUG[1];


extern __device__ void loadTemplateMatrix(volatile double KE[24][24], int Cid);

template<int N>
__device__ int gridPos2id(int x, int y, int z) {
	return x + y * N + z * N*N;
}

//  suppose Uworst, Fworst is prepared in U, F
__global__ void computeSensitivity_kernel(int nv, float* rholist, double mu, float* sens) {
	//nv: n_nodes
	int tid = blockDim.x*blockIdx.x + threadIdx.x;

	__shared__ double KE[24][24];

	loadTemplateMatrix(KE, 0);

	if (tid >= nv) return;

	int vid = tid;

	int vneigh[27];
	for (int i = 0; i < 27; i++) {
		vneigh[i] = gV2V[i][vid];
		// printf("gV2V[%d][%d] = %d\n", i, vid, vneigh[i]);
	}
    
	// int maxeid = 0;
	// traverse incident elements of vertex
	for (int i = 0; i < 8; i++) {
		double partialSens = 0;

		int eid = gV2E[i][vid];
		// if(eid > maxeid) maxeid = eid;
		// printf("gV2E[%d][%d] = %d\n", i, vid, eid);
		if (eid == -1) continue;
		double Ui[3] = { gU[0][vid],gU[1][vid],gU[2][vid] };
		double penal = power_penalty[0] * powf(rholist[eid], power_penalty[0] - 1);

		// compute partial node force (element i's contribution) K_\rho * Uworst on vi
		double KrhoU[3] = { 0. };
		// vertex self id in neihbor element i
		int vi = 7 - i;
		// vertex neighbor id in element i, traverse them and compute the corresponding node force on self
		for (int vj = 0; vj < 8; vj++) {
			int vjlid = gridPos2id<3>(i % 2 + vj % 2, i % 4 / 2 + vj % 4 / 2, i / 4 + vj / 4);
			double Uj[3];
			for (int k = 0; k < 3; k++) Uj[k] = gU[k][vneigh[vjlid]];
			for (int krow = 0; krow < 3; krow++) {
				for (int kcol = 0; kcol < 3; kcol++) {
					KrhoU[krow] += KE[vi * 3 + krow][vj * 3 + kcol] * Uj[kcol];
				}
			}
		}
		

		for (int k = 0; k < 3; k++) KrhoU[k] *= penal;

#if 0
		// sensitivity  u_worst * dK/drho * u_worst
		for (int k = 0; k < 3; k++) partialSens += Ui[k] * KrhoU[k];

		// sensitivity  - 2 mu * u_worst * dK/drho * K * u_worst
		for (int k = 0; k < 3; k++) partialSens += -2 * mu * KrhoU[k] * gFworst[k][vid];

		// sensitivity  - lambda * N * dK/drho * u_worst
		for (int k = 0; k < 3; k++) {
			partialSens += -KrhoU[k] * gU[k][vid];
		}
#else
		// sensitivity  - u_worst * dK/drho * u_worst
		for (int k = 0; k < 3; k++) partialSens -= Ui[k] * KrhoU[k];

#endif

		atomicAdd(sens + eid, float(partialSens));
		// TODO_yyy
		// atomicAdd(sens + 4*eid, float(partialSens));
		// atomicAdd(sens + 4*eid+1, float(partialSens));
		// atomicAdd(sens + 4*eid+2, float(partialSens));
		// atomicAdd(sens + 4*eid+3, float(partialSens));
	}
    // printf("maxeid = %d\n", maxeid);
}

//  suppose Uworst, Fworst is prepared in U, F
__global__ void computeSensitivity_kernel_cloak1(int nv, float* rholist, float* c11list, float* c12list, float* c44list, double mu, float* sens, float* sens_C11, float* sens_C12, float* sens_C44) {
	//nv: n_nodes
	int tid = blockDim.x*blockIdx.x + threadIdx.x;

	__shared__ double KE11[24][24]; 
	__shared__ double KE12[24][24]; 
	__shared__ double KE44[24][24]; 

	loadTemplateMatrix(KE11,1);
	loadTemplateMatrix(KE12,2);
	loadTemplateMatrix(KE44,3);

	if (tid >= nv) return;

	int vid = tid;

	int vneigh[27];
	for (int i = 0; i < 27; i++) {
		vneigh[i] = gV2V[i][vid];
		// printf("gV2V[%d][%d] = %d\n", i, vid, vneigh[i]);
	}

	// traverse incident elements of vertex
	for (int i = 0; i < 8; i++) {
		double partialSens = 0;
		double partialSens11 = 0;
		double partialSens12 = 0;
		double partialSens44 = 0;

		int eid = gV2E[i][vid];
		// printf("gV2E[%d][%d] = %d\n", i, vid, eid);
		if (eid == -1) continue;
		double Ui[3] = { gU[0][vid],gU[1][vid],gU[2][vid] };
		double penal = power_penalty[0] * powf(rholist[eid], power_penalty[0] - 1);
		double penal0 = powf(rholist[eid], power_penalty[0]);
		double c11 = c11list[eid];
		double c12 = c12list[eid];
		double c44 = c44list[eid];

		// compute partial node force (element i's contribution) K_\rho * Uworst on vi
		double KrhoU[3] = { 0. };
		double Kc11U[3] = { 0. };
		double Kc12U[3] = { 0. };
		double Kc44U[3] = { 0. };
		// vertex self id in neihbor element i
		int vi = 7 - i;
		// vertex neighbor id in element i, traverse them and compute the corresponding node force on self
#if 0
		for (int vj = 0; vj < 8; vj++) {
			int vjlid = gridPos2id<3>(i % 2 + vj % 2, i % 4 / 2 + vj % 4 / 2, i / 4 + vj / 4);
			double Uj[3];
			for (int k = 0; k < 3; k++) Uj[k] = gU[k][vneigh[vjlid]];
			for (int krow = 0; krow < 3; krow++) {
				for (int kcol = 0; kcol < 3; kcol++) {
					KrhoU[krow] += (c11 * KE11[vi * 3 + krow][vj * 3 + kcol] * Uj[kcol] + \
					                c12 * KE12[vi * 3 + krow][vj * 3 + kcol] * Uj[kcol] + c44 * KE44[vi * 3 + krow][vj * 3 + kcol] * Uj[kcol]);
					// Kc11U[krow] += (c11 * KE11[vi * 3 + krow][vj * 3 + kcol] * Uj[kcol] + \
					//                 c12 * KE12[vi * 3 + krow][vj * 3 + kcol] * Uj[kcol] + c44 * KE44[vi * 3 + krow][vj * 3 + kcol] * Uj[kcol]);
				    // 感觉这里的公式推错了。。。
					// 增加位数输出了一下：[sensitivity_C11] max = 0.0000000024863162639832125933025963604450225830078125000000000000000000000000000000000000000000000000
				    // 可见并没有算错，由于c11，c12，c44很大（~1e6），由灵敏度公式，他们的灵敏度确实要比rho的灵敏度小很多，这也说明应该归一化
					Kc11U[krow] += KE11[vi * 3 + krow][vj * 3 + kcol] * Uj[kcol];
					Kc12U[krow] += KE12[vi * 3 + krow][vj * 3 + kcol] * Uj[kcol];
					Kc44U[krow] += KE44[vi * 3 + krow][vj * 3 + kcol] * Uj[kcol];
				}
			}
		}

		for (int k = 0; k < 3; k++){
			KrhoU[k] *= penal;
			Kc11U[k] *= penal0;
			Kc12U[k] *= penal0;
			Kc44U[k] *= penal0;
		} 

#if 0
		// sensitivity  u_worst * dK/drho * u_worst
		for (int k = 0; k < 3; k++) partialSens += Ui[k] * KrhoU[k];

		// sensitivity  - 2 mu * u_worst * dK/drho * K * u_worst
		for (int k = 0; k < 3; k++) partialSens += -2 * mu * KrhoU[k] * gFworst[k][vid];

		// sensitivity  - lambda * N * dK/drho * u_worst
		for (int k = 0; k < 3; k++) {
			partialSens += -KrhoU[k] * gU[k][vid];
		}
#else
		// sensitivity  - u_worst * dK/drho * u_worst
		for (int k = 0; k < 3; k++){
			partialSens -= Ui[k] * KrhoU[k];
			partialSens11 -= Ui[k] * Kc11U[k];
			partialSens12 -= Ui[k] * Kc12U[k];
			partialSens44 -= Ui[k] * Kc44U[k];
		} 

#endif
#else
for (int vj = 0; vj < 8; vj++) {
			int vjlid = gridPos2id<3>(i % 2 + vj % 2, i % 4 / 2 + vj % 4 / 2, i / 4 + vj / 4);
			double Uj[3];
			for (int k = 0; k < 3; k++) Uj[k] = gU[k][vneigh[vjlid]];
			for (int krow = 0; krow < 3; krow++) {
				for (int kcol = 0; kcol < 3; kcol++) {
					KrhoU[krow] += (c11 * KE11[vi * 3 + krow][vj * 3 + kcol] * Uj[kcol] + \
					                c12 * KE12[vi * 3 + krow][vj * 3 + kcol] * Uj[kcol] + c44 * KE44[vi * 3 + krow][vj * 3 + kcol] * Uj[kcol]);
					Kc11U[krow] += KE11[vi * 3 + krow][vj * 3 + kcol] * Uj[kcol];
					Kc12U[krow] += KE12[vi * 3 + krow][vj * 3 + kcol] * Uj[kcol];
					Kc44U[krow] += KE44[vi * 3 + krow][vj * 3 + kcol] * Uj[kcol];
				}
			}
		}

		for (int k = 0; k < 3; k++){
			KrhoU[k] *= penal;
			Kc11U[k] *= penal0;
			Kc12U[k] *= penal0;
			Kc44U[k] *= penal0;
		} 
		// sensitivity  - u_worst * dK/drho * u_worst
		for (int k = 0; k < 3; k++){
			partialSens -= Ui[k] * KrhoU[k];
			partialSens11 -= Ui[k] * Kc11U[k];
			partialSens12 -= Ui[k] * Kc12U[k];
			partialSens44 -= Ui[k] * Kc44U[k];
		} 
#endif

		atomicAdd(sens + eid, float(partialSens));
		// atomicAdd(sens_C11 + eid, float(partialSens));
		atomicAdd(sens_C11 + eid, float(partialSens11));
		atomicAdd(sens_C12 + eid, float(partialSens12));
		atomicAdd(sens_C44 + eid, float(partialSens44));
		// [sensitivity] max = 0.044646
        // [sensitivity_C11] max = 0.044646
		// [sensitivity_C12] max = 0.000000
		// [sensitivity_C44] max = 0.000000
		// 这说明partialSensxx没算对，可能全都是0；
	}
}

void computeSensitivity(void) {
	grids[0]->use_grid();
	// now, suppose Uworst, Fworst is prepared, N^T * Lambda is in U,
	// copy Fworst=KUworst to F
	//grids[0]->v3_copy(grids[0]->getWorstForce(), grids[0]->getForce());

	// init sensitivity to zero
	init_array(grids[0]->getSens(), float{ 0 }, grids[0]->n_rho());

	size_t grid_size, block_size;
	make_kernel_param(&grid_size, &block_size, grids[0]->n_nodes(), 512);
    if(params.cloak == 0){
		// printf("computeSensitivity_kernel\n");
		computeSensitivity_kernel << <grid_size, block_size >> > (grids[0]->n_nodes(), grids[0]->getRho(), grids[0]->_keyvalues["mu"], grids[0]->getSens());
	}
	else if(params.cloak == 1 ||params.cloak == 2){
		// printf("computeSensitivity_kernel_cloak1\n");
		computeSensitivity_kernel_cloak1 << <grid_size, block_size >> > (grids[0]->n_nodes(), grids[0]->getRho(), grids[0]->getC11(), grids[0]->getC12(), grids[0]->getC44(), grids[0]->_keyvalues["mu"], \
	                                                              grids[0]->getSens(), grids[0]->getSens_C11(), grids[0]->getSens_C12(), grids[0]->getSens_C44());
	}
	
	
	cudaDeviceSynchronize();
	cuda_error_check;

	// DEBUG
	//grids[0]->sens2matlab("sens");

	// filter sensitivity
	grids[0]->filterSensitivity(params.filter_radius);
	
	// DEBUG
	grids[0]->sens2matlab("sensfilt");
}


__global__ void trySensMultiplier_kernel(
	int nv, const float* rholist, float* g_sens, float g_thres, float step, float damp, float rhomin, float* newrho) {
	int tid = blockDim.x*blockIdx.x + threadIdx.x;
	if (tid >= nv) return;

	int eid = gV2E[7][tid];

	if (eid == -1) { return; }

	float g = g_sens[eid];

	if (g > 0) g = 0;

	g = abs(g);

	float rhoold = rholist[eid];

	float rhonew = rhoold * powf(g / g_thres, damp);

	rhonew = clamp(rhonew, rhoold - step, rhoold + step);

	rhonew = clamp(rhonew, rhomin, 1.f);

	if (gEflag[0][eid] & grid::Grid::Bitmask::mask_shellelement) rhonew = 1;

	newrho[eid] = rhonew;
}


float updateDensities(float Vgoal) {
	grids[0]->use_grid();

	size_t grid_size, block_size;
	make_kernel_param(&grid_size, &block_size, grids[0]->n_nodes(), 512);

	float Vratio = 2;

	float g_thres_low = 0;
	float g_thres_upp = 1;

	// compute old volume ratio
	double* sum = (double*)grid::Grid::getTempBuf(sizeof(double) * grids[0]->n_rho() / 100);
	double Vold = parallel_sum_d(grids[0]->getRho(), sum, grids[0]->n_rho()) / grids[0]->n_rho();
	printf("Vold = %f\n", Vold);

	// compute maximal sensitivity
	float* maxdump = (float*)grid::Grid::getTempBuf(sizeof(float)* grids[0]->n_rho() / 100);
	float g_max = parallel_maxabs(grids[0]->getSens(), maxdump, grids[0]->n_rho());

	g_thres_upp = g_max;

	printf("[sensitivity] max = %f\n", g_max);

	float g_thres = (g_thres_low + g_thres_upp) / 2;

	// iteration counter
	int itn = 0;

	// bisection search sensitivity multiplier
	do  {
		// update sensitivity threshold
		g_thres = (g_thres_low + g_thres_upp) / 2;

		printf("-- searching multiplier g = %4.4e", g_thres);

		float* newrho = (float*)grid::Grid::getTempBuf(sizeof(float)* grids[0]->n_rho());

		// update new rho
		trySensMultiplier_kernel << <grid_size, block_size >> > (
			grids[0]->n_nodes(), grids[0]->getRho(), grids[0]->getSens(), g_thres, params.design_step, params.damp_ratio, params.min_rho, newrho);
		cudaDeviceSynchronize();
		cuda_error_check;

		// compute new volume ratio
		Vratio = dump_array_sum(newrho, grids[0]->n_rho()) / grids[0]->n_rho();

		printf(", V = %f  goal %f\n", Vratio, Vgoal);

		if (Vratio > Vgoal) {
			g_thres_low = g_thres;
		}
		else if (Vratio < Vgoal) {
			g_thres_upp = g_thres;
		}
	} while (abs(Vratio - Vgoal) > 1e-4 && itn++ < 30);

	// update densities according to new sensitivity
	trySensMultiplier_kernel << <grid_size, block_size >> > (grids[0]->n_nodes(), grids[0]->getRho(), grids[0]->getSens(), g_thres, params.design_step, params.damp_ratio, params.min_rho, grids[0]->getRho());
	
	double* sumnew = (double*)grid::Grid::getTempBuf(sizeof(double) * grids[0]->n_rho() / 100);
	double Vnew = parallel_sum_d(grids[0]->getRho(), sumnew, grids[0]->n_rho()) / grids[0]->n_rho();
	printf("Vnew = %f\n", Vnew);
	
	cudaDeviceSynchronize();
	cuda_error_check;
	
	return g_thres;
}


//TODO_yyy
float updateDensities_yyy(float Vgoal) {
	grids[0]->use_grid();

	size_t grid_size, block_size;
	make_kernel_param(&grid_size, &block_size, grids[0]->n_nodes(), 512);

	float Vratio = 2;

	float g_thres_low = 0;
	float g_thres_upp = 1;

	// compute old volume ratio
	double* sum = (double*)grid::Grid::getTempBuf(sizeof(double) * grids[0]->n_rho() / 100);
	printf("grids[0]->n_rho() = %d\n", grids[0]->n_rho());
	double Vold = parallel_sum_d(grids[0]->getRho(), sum, grids[0]->n_rho()) / (grids[0]->n_rho());

	// compute maximal sensitivity
	float* maxdump = (float*)grid::Grid::getTempBuf(sizeof(float)* grids[0]->n_rho()/ 100);
	float g_max = parallel_maxabs(grids[0]->getSens(), maxdump, grids[0]->n_rho());

	g_thres_upp = g_max;

	printf("[sensitivity] max = %f\n", g_max);

	float g_thres = (g_thres_low + g_thres_upp) / 2;

	// iteration counter
	int itn = 0;

	// bisection search sensitivity multiplier
	do  {
		// update sensitivity threshold
		g_thres = (g_thres_low + g_thres_upp) / 2;

		printf("-- searching multiplier g = %4.4e", g_thres);

		float* newrho = (float*)grid::Grid::getTempBuf(sizeof(float)* grids[0]->n_rho());

		// update new rho
		trySensMultiplier_kernel << <grid_size, block_size >> > (
			grids[0]->n_nodes(), grids[0]->getRho(), grids[0]->getSens(), g_thres, params.design_step, params.damp_ratio, params.min_rho, newrho);
		cudaDeviceSynchronize();
		cuda_error_check;

		// compute new volume ratio
		Vratio = dump_array_sum(newrho, grids[0]->n_rho()) / (grids[0]->n_rho());

		printf(", V = %f  goal %f\n", Vratio, Vgoal);

		if (Vratio > Vgoal) {
			g_thres_low = g_thres;
		}
		else if (Vratio < Vgoal) {
			g_thres_upp = g_thres;
		}
	} while (abs(Vratio - Vgoal) > 1e-4 && itn++ < 30);

	// update densities according to new sensitivity
	trySensMultiplier_kernel << <grid_size, block_size >> > (grids[0]->n_nodes(), grids[0]->getRho(), grids[0]->getSens(), g_thres, params.design_step, params.damp_ratio, params.min_rho, grids[0]->getRho());
	cudaDeviceSynchronize();
	cuda_error_check;
	
	return g_thres;
}


extern void matlab_utils_test(void);

void selfTest(void)
{
	printf("-- Self testing...\n");
	using namespace grid;

	std::vector<int> arr(10000, 0xaaaaaaaa);

	BitSAT<int> bits(arr);

	printf("-- host bits total = %d\n", bits.total());

	gBitSAT<int> gbits(bits._bitArray, bits._chunkSat);

	{
		std::vector<int> bitscheck(bits._bitArray.size());
		cudaMemcpy(bitscheck.data(), gbits._bitarray, sizeof(int) * bitscheck.size(), cudaMemcpyDeviceToHost);
		//printf("%p ->\n", gbits._bitarray);
		//for (int i = 0; i < bitscheck.size(); i++) printf("%d ", bitscheck[i]);
		//printf("\n");
	}

	devArray_t<int*, 1> gcount;
	cudaMalloc(&gcount[0], bits._bitArray.size() * BitCount<int>::value * sizeof(int));

	size_t grid_size, block_size;
	make_kernel_param(&grid_size, &block_size, bits._bitArray.size() * BitCount<int>::value, 128);

	auto kernel = [=] __device__(int tid) {
		if (blockIdx.x == 0 && threadIdx.x == 0) {
			//printf("_bitarray = %p ; _chunksat = %p\n", gbits._bitarray, gbits._chunksat);
			//printf("firstOne = %d\n", ::firstOne<sizeof(int) * 8>::value);
		}
		gcount[0][tid] = gbits[tid];
	};
	traverse_noret << <grid_size, block_size >> > (bits._bitArray.size() * BitCount<int>::value, kernel);
	cudaDeviceSynchronize();
	cuda_error_check;

	std::vector<int> counts(bits._bitArray.size() * BitCount<int>::value);
	cudaMemcpy(counts.data(), gcount[0], sizeof(int) * bits._bitArray.size() * BitCount<int>::value, cudaMemcpyDeviceToHost);

	bool pass_test = true;
	for (int i = 0; i < counts.size(); i++) {
		//printf("[%d] : %d\n", i, counts[i]);
		if (counts[i] != bits[i]) {
			pass_test = false;
			break;
		}
	}

	gbits.destroy();
	gcount.destroy();

	cuda_error_check;

	matlab_utils_test();

	// test GraftArray
	{
		std::vector<int> hostbuf(10000);
		int* _bufdev;
		cudaMalloc(&_bufdev, sizeof(int)*hostbuf.size());
		int baselen = hostbuf.size();
		auto kern = [=] __device__(int tid) {
			int rl = baselen / 125;
			GraftArray<int, 25, 5> p(_bufdev, rl);
			int id[3] = { tid % rl, tid / rl % 5,tid / rl / 5 };
			p[id[2]][id[1]][id[0]] = tid;
		};
		size_t grid_size, block_size;
		make_kernel_param(&grid_size, &block_size, hostbuf.size(), 512);
		traverse_noret << <grid_size, block_size >> > (hostbuf.size(), kern);
		cudaDeviceSynchronize();
		cuda_error_check;
		cudaMemcpy(hostbuf.data(), _bufdev, sizeof(int) * hostbuf.size(), cudaMemcpyDeviceToHost);

		bool fail = false;
		for (int i = 0; i < hostbuf.size(); i++) {
			if (hostbuf[i] != i) {
				fail = true; break;
			}
		}
		if (fail) {
			printf("-- GraftArray test failed\n");
		}
		pass_test &= !fail;

		cudaFree(_bufdev);
	}

	if (pass_test) {
		printf("-- Pass test\n");
	}
	else {
		printf("-- Test failed\n");
	}

}

// upload template matrix and power penalty coefficient
void uploadTemplateMatrix(void)
{
	double element_len = grids.elementLength();
	if(params.cloak == 0){
		printf("params.cloak = %d\n", params.cloak);
		initTemplateMatrix(element_len, gpu_manager, params.youngs_modulu, params.poisson_ratio);
	}
	else if(params.cloak == 1 || params.cloak == 2){
		printf("params.cloak = %d\n", params.cloak);
		initTemplateMatrix_cloak1(element_len, gpu_manager, params.youngs_modulu, params.poisson_ratio);
	}
	
	if(params.cloak == 0){
		const double* ke = getTemplateMatrixElements();
	    cudaMemcpyToSymbol(gTemplateMatrix, ke, sizeof(gTemplateMatrix));
	    cuda_error_check;
	}
	else if(params.cloak == 1 || params.cloak == 2){
		const double* ke11 = getTemplateMatrixElements11();
	    cudaMemcpyToSymbol(gTemplateMatrix11, ke11, sizeof(gTemplateMatrix11));
		const double* ke12 = getTemplateMatrixElements12();
	    cudaMemcpyToSymbol(gTemplateMatrix12, ke12, sizeof(gTemplateMatrix12));
		const double* ke44 = getTemplateMatrixElements44();
	    cudaMemcpyToSymbol(gTemplateMatrix44, ke44, sizeof(gTemplateMatrix44));
	    cuda_error_check;
	}
	

	// upload power penalty
	float power = params.power_penalty;
	cudaMemcpyToSymbol(power_penalty, &power, sizeof(power_penalty));
	cuda_error_check;
}

void setDEBUG(bool debug)
{
	int a = 0;
	if (debug) a = 1;
	cudaMemcpyToSymbol(gDEBUG, &a, sizeof(int));
}


__global__ void checkAjointKernel(int n_gsvertices, double mu, devArray_t<double*, 3> vdst) {
	int tid = blockDim.x * blockIdx.x + threadIdx.x;

	if (tid >= n_gsvertices) return;

	for (int i = 0; i < 3; i++) {
		double kku = gF[i][tid];
		double f = vdst[i][tid];
		double fworst = gFworst[i][tid];
		vdst[i][tid] = 2 * fworst - f - 2 * mu * kku;
	}
}

// supporst N^T lambda is in U,  uworst is in Uworst, Kuworst is in Fworst
bool checkAdjointVariable(void) {
	grids[0]->use_grid();
	devArray_t<double*, 3> vdst, uback;
	for (int i = 0; i < 3; i++) {
		cudaMalloc(&vdst[i], sizeof(double) * grids[0]->n_gsvertices);
		cudaMalloc(&uback[i], sizeof(double) * grids[0]->n_gsvertices);
	}
	// backup adjoint displacement
	grids[0]->v3_copy(grids[0]->getDisplacement(), uback._data);
	// KNlam in vdst
	grids[0]->applyK(grids[0]->getDisplacement(), grids[0]->getForce());
	grids[0]->v3_copy(grids[0]->getForce(), vdst._data);
	grids[0]->resetDirchlet(vdst._data);

	// KKu is in F
	grids[0]->v3_copy(grids[0]->getWorstForce(), grids[0]->getDisplacement());
	grids[0]->applyK(grids[0]->getDisplacement(), grids[0]->getForce());
	grids[0]->resetDirchlet(grids[0]->getForce());
	double mu = grids[0]->_keyvalues["mu"];
	
	size_t grid_size, block_size;
	make_kernel_param(&grid_size, &block_size, grids[0]->n_gsvertices, 512);
	checkAjointKernel<<<grid_size,block_size>>>(grids[0]->n_gsvertices, mu, vdst);
	cudaDeviceSynchronize();
	cuda_error_check;
	grids[0]->v3_toMatlab("vadj", vdst._data);
	bool vnorm = grids[0]->v3_norm(vdst._data);
	bool passCheck = vnorm < 1e-6;

	grids[0]->v3_copy(uback._data, grids[0]->getDisplacement());

	vdst.destroy();
	uback.destroy();

	return passCheck;
}


