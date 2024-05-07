// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// app.dart
// The main app widget for the ROHD Wave Viewer.
//
// 2024 April
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rohd_wave_viewer/src/modules/home/view/home.dart';
import 'package:rohd_wave_viewer/src/modules/rohd_module/bloc/rohd_module_bloc.dart';
import 'package:module_structure_repository/module_structure_repository.dart';
import 'package:rohd_wave_viewer/src/modules/signal/bloc/signal_bloc.dart';
import 'package:rohd_wave_viewer/src/modules/waveform/bloc/waveform_module_bloc.dart';

class App extends StatelessWidget {
  const App({required this.moduleStructureRepository, super.key});

  final ModuleStructureRepository moduleStructureRepository;

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<RohdModuleBloc>(
          create: (context) => RohdModuleBloc(
            moduleStructureRepository: moduleStructureRepository,
          ),
        ),
        BlocProvider<SignalBloc>(
          create: (context) => SignalBloc(moduleStructureRepository),
        ),
        BlocProvider<WaveformModuleBloc>(
          create: (context) => WaveformModuleBloc(
              moduleStructureRepository: moduleStructureRepository),
        ),
      ],
      child: MaterialApp(
        title: 'ROHD Wave viewer',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.white),
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.transparent,
            elevation: 0,
          ),
          textTheme: GoogleFonts.robotoTextTheme(Theme.of(context).textTheme),
        ),
        initialRoute: '/',
        routes: {
          '/': (_) => const Scaffold(body: WaveFormViewerPage()),
        },
      ),
    );
  }
}
