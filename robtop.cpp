﻿// robtop.cpp : 此文件包含 "main" 函数。程序执行将在此处开始并结束。
//

#include <iostream>
#include <string>
#include "config_parser.h"
#include "optimization.h"
#include "test_utils.h"

extern void version_info(void);
std::string version_hash(void);
extern void init_cuda(void);
extern void hello_extern(void);

config_parser_t parser;


int main(int argc, char** argv)
{
	version_info();
	init_cuda();

	selfTest();

	hello_extern();

	parser.parse(argc, argv);

	setParameters(
		FLAGS_volume_ratio, FLAGS_vol_reduction, FLAGS_design_step, FLAGS_filter_radius, FLAGS_damp_ratio, FLAGS_power_penalty, FLAGS_min_density,
		FLAGS_gridreso, FLAGS_youngs_modulus, FLAGS_poisson_ratio, FLAGS_cloak, FLAGS_shell_width,
		FLAGS_logdensity, FLAGS_logcompliance);
    
	setGridParameters(FLAGS_cloak);
	
	setOutpurDir(FLAGS_outdir);

	setWorkMode(FLAGS_workmode);

	setBoundaryCondition(parser.inFixArea, parser.inLoadArea, parser.loadField);

	buildGrids(parser.mesh_vertices, parser.mesh_faces);

	uploadTemplateMatrix();

	logParams("cmdline", version_hash(), argc, argv);
	printf("0");

	TestSuit::testMain(FLAGS_testname);
    printf("1");

	optimization();
}

