# Large-Scale Worst-Case Topology Optimization



## Compilation

The source can be compiled using CMake, while most of the dependcies has be packed into a conda environment. You can activate it by :

```bash
conda env create -f environment.yml
conda activate robtop
```

Then configure and build the project in conda environment:

```bash
mkdir build
cd buld
cmake .. -DUSE_CONDA=ON 
make -j4
```





## Usage

### Option

* `-meshfile`:  The input mesh model.
* `-jsonfile`:  The input boundary condition in Json format.

* `-gridreso`:  default=`200`, set the grid resolution along the longest axis (**must<1024**)
* `-volume_ratio`: The  goal volume ratio of optimized model
* `-outdir`: The output directory of the results.
* `-workmode`: 4 alternative mode (`wscf`/`wsff`/`nscf`/`nsff`), `ws/ns` means with/no support(fixed) boundary, `cf/ff` means constrain force direction to surface normal or not.
* `-filter_radius`: default=`2`, the sensitivity filter radius in the unit of the voxel length. 
* `-damp_ratio`:  default=`0.5`, the damp ratio of the  Optimality Criteria method
* `-design_step`:  default=`0.03`, the change limit (maximal step length) when updating the density.
* `-shell_width`: default=`3`, the shell width to be enforced during the optimization, given in the unit of the voxel length.
* `-poisson_ratio`:default=`0.4`, Poisson ratio of the solid material.
* `-youngs_modulus`: default=`1e6`, Young's Modulus of the solid material.
* `-min_density`: default=`1e-3`,  minimal density value to avoid numerical problem.
* `-power_penalty`: default=`3`, the power exponent of density penalty.
* `-[no]logdensity`: output density field in each iteration or not.
* `-testname`: additional test suits. For example, `-testname=testordtop` will do general topology optimization, not worst-case optimization.



### example

1. Copy the compiled executable to `./bench` 

2. Copy the dependent shared library to `./bench` .

3. Run the following command in CMD or shell

   * ##### Bridge Example

     ###### distribute force Optimization

     ```
     ./robtop -jsonfile=./mirbridge/config2.json -meshfile=./mirbridge/mirbridge.obj -outdir=./result/mirbridge/distri/ -power_penalty=3 -volume_ratio=0.4 -filter_radius=2 -gridreso=511 -damp_ratio=0.5 -shell_width=0 -workmode=wscf -poisson_ratio=0.4 -design_step=0.06 -vol_reduction=0.05 -min_density=1e-3 -logdensity -nologcompliance -testname=testdistributeforce
     ```

     ###### Worst-Case Optimization

     ```
     ./robtop -jsonfile=./mirbridge/config2.json -meshfile=./mirbridge/mirbridge.obj -outdir=./result/mirbridge/rob/ -power_penalty=3 -volume_ratio=0.4 -filter_radius=2 -gridreso=511 -damp_ratio=0.5 -shell_width=0 -workmode=wscf -design_step=0.06 -poisson_ratio=0.4 -vol_reduction=0.05 -min_density=1e-3 -logdensity -nologcompliance -testname=None
     
     ```
     
     



## Dependency

* CGAL 
* Trimesh2 (https://github.com/Forceflow/trimesh2.git)
* CUDA 11
* OpenVDB 
* OpenMesh
* glm (https://glm.g-truc.net/0.9.9/)
* Boost
* RapidJson
* gflags
* Spectra (https://github.com/yixuan/spectra.git)



## Docker Image

* We provide a docker environment for compiling the code and reproducing the results easily, the docker image can be generated by building the Dockerfile:

  ```shell
  docker build -f ./Dockerfile -t robtop_dev .
  ```

  entering the image with GPU enabled:

  ```shell
  docker run -it --gpus=all robtop_dev /bin/bash
  ```

  the source code is located in `/home/src/robtop`。



* There is also a prebuilt version which can be obtained by 

  ```
  docker pull dockzd/robtop:2.0
  ```

   This image only contains the executable file and runtime libraries.



## Note 

To see our original source of paper "[Large-Scale Worst-Cast Topology Optimization](https://onlinelibrary.wiley.com/doi/abs/10.1111/cgf.14698)", Please checkout tag `CGF-Paper-Version` . The source tree has been refactored.



## Reference

* This repository incorporates a voxelization routine that credits the original source, [cuda_voxelizer](https://github.com/Forceflow/cuda_voxelizer).


## Notes yyy
1.
运行readme中的第一个例子（distribute force Optimization）,会在finished后出现一堆同样的错误：
```
CUDA error occured at line 30 in file /home/yyy/Projects/robtop/mem/gpu_manager_t.cu, error type cudaErrorCudartUnloading
```
一开始以为finished就是optimization()结束了，后来发现不是，只是TestSuit::testMain(FLAGS_testname)结束，optimization()根本没开始。

逐一排查，	
TestSuit::testMain(FLAGS_testname)中的
```
else if (testname == "testdistributeforce") {
		testDistributeForceOpt();
	}
```
能正常结束，但optimization()无法开始。
初步判断错误处在TestSuit::testMain(FLAGS_testname)结束时一些指针的生命周期结束，自动调用deleteDeviceMemory，而这里有问题。

其实这也不是什么问题，试了设置-testname=None，即跳过TestSuit::testMain(FLAGS_testname)，直接进入optimization()。这个问题只在优化结束时才出现，似乎并不影响结果。

另，看看testDistributeForceOpt()和optimization()有什么区别，感觉testDistributeForceOpt()已经做完优化了。

OK，感觉区别基本上只在于		
```
void TestSuit::testDistributeForceOpt(void){
  ...
  while (rel_res > 1e-2 && femit++ < 50) {
		rel_res = grids.v_cycle(1, 1);
	}
  ...
}
```
和
```
void optimization(void) {
  ...
  double c_worst = modifiedPM();
  ...
}
```
而modifiedPM的主题基本上和前面那个是一样的，只是最大循环次数从50改成了500，并加了一些输出和一些不太懂的东西


2.
modifiedPM中的change of force是什么，这难道不是有限元求解位移吗，为什么看起来像求解force，force变化很小时认为收敛。

。。。，你看一下robtop论文的Algorithm 1就明白了。

3.
为什么不一样：
```
_gridlayer[0]->n_elements = 224028
_gridlayer[0]->n_gselements = 224128
```
你看[0] Enumerating GS subset里e后面的数，括号里的8个数加起来=224128，括号外的加起来=224028。这应该是eight-color Gauss-Seidel relaxation，在homo3d的文章里有讲。

4.
test_utils.cpp: // #include "lib.cuh" //now we know that including a .cuh in .cpp is not recommended
如果我就是想用lib.cuh里的函数，怎么办呢？ 用外部函数：extern double dump_array_sum(float* dump, size_t n);

5.
在testDistributeForceOpt()中使用updateDensities_MMA()时遇到的问题：
计算体积约束及其导数：  
尝试1：
```
		float gvalval = float(Vratio) / Vgoal - 1;
		float* gval = &(gvalval);
		float dvdx[grids[0]->n_gselements];
		for(int i=0; i<grids[0]->n_gselements; i++){
			dvdx[i] = 1 / (grids[0]->n_gselements * Vgoal);
		}
		float *dgdx[1] = {dvdx};
    updateDensities_MMA(1, grids[0]->n_gselements, 1, 0, 1000, 1, itn,  grids[0]->getRho(), grids[0]->getSens(), gval, dgdx);
```
错误！gval和dgdx必须是GPU上的指针。  
尝试2（作为尝试1的对照试验）：
```
		float *gval = grids[0]->getRho();
		float *dgdx[1] = {gval}; 
    updateDensities_MMA(1, grids[0]->n_gselements, 1, 0, 1000, 1, itn,  grids[0]->getRho(), grids[0]->getSens(), gval, dgdx);
```
可以正常使用MMA了。
尝试3：
```
float* gval = (float*)grid::Grid::getTempBuf(sizeof(float));
*(gval) = float(Vratio) / Vgoal - 1;
```
错误！ Segmentation fault (core dumped)。gval是GPU上的指针，不能直接用*(gval)操作其指向的内容。  
在Host(CPU)和Device(GPU)间传递数据要用：
```
cudaMemcpy(dst, src, size, cudaMemcpyHostToDevice);
cudaMemcpy(dst, src, size, cudaMemcpyDeviceToHost);
```