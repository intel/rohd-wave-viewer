# Design Architecture

This document describe how ROHD Wave Viewer is designed using the Flutter BLOC architecture. In the BLOC architecture, we see a clear separation between application layer, domain layer, and data layer.

## Application Layer

This layer contains all of the application-specific features and use cases. Each feature generally consists of some UI and business logic. Features should generally be independent of other features so that they can easily be added/removed without impacting the rest of the codebase. Within each feature, the state of the feature along with any business logic is managed by bloc. Blocs interact with zero or more repositories. Blocs react to events and emit states which trigger changes in the UI. Widgets within each feature should generally only depend on the corresponding bloc and render UI based on the current state. The UI can notify the bloc of user input via events.

This later define the `ui` and `bloc` of the application. It should live in the `lib/modules/{name of your module}`. Inside the folder, there are  `bloc` and `view`. View folder is pretty straight forwards where it describe the widget of your UI whenever state changes.

As of Bloc, it consists of event, state and bloc. Event is actions that triggered the state changes. State is the data, or condition that happened when an event triggered. All the business logic of how event and state communicate is detailed in bloc.

## Repository Layer / Domain Layer

This layer combines one or more data providers and applies "business rules" to the data. Each component in this layer is called a repository and each repository generally manages a single domain. Packages in the repository layer should generally only interact with the data layer. In this example, our repository layer consists of the `module_structure_repository` package. Repository layer will provide business value through the mix and match of the data providers.

In here, I define the common use function like `getSignalsBySelectedModule` or `getModuleStructure` which is kinda the same no matter which data provider you are using.

## Data Layer

This layer is the lowest layer and is responsible for retrieving raw data from external sources such as a databases, APIs, and more. Packages in the data layer generally should not depend on any UI and can be reused and even published on pub.dev as a standalone package. This layer defines the model blueprint of the waveform (`packages/module_structure_api`) that tell how waveform how its going to look like. You can think of this as a data provider, a layer that provides and gives the necessary data for waveform to be usable.

You should be writting your API that talk to other file system here or extends from this model structure.

## Directory Structure

BLOC makes domain layer and data layer seperate as a packages. This follows the Single Responsibility Principle by SOLID which make testing easier. With riverpod (as was used in intel/rohd's dev tool), its harder to test as too many dependency. Hence, this is the directory structure:

```cmd
/lib
  /src
  /modules
    /home: The home page that shows the partition of the panel
      /view
    /rohd_module: ROHD Module tree
      /bloc
      /view
    /shared: Reusable and shared flutter widgets 
      /widgets
    /signal: Signals available and action from a module
      /bloc
      /view
    /waveform: Waveform of the widgets. Use Flutter CustomPainter here.
      /bloc
      /view
/packages
  - module_structure_api: connection between rohd debugger, vcd happened in data layer (Data Layer) - Note: Seems like every data layer output a stream/future. Export a generic interface for interacting / managing todos. It support other implementation in the future `VCDWaveformAPI` or `ROHDDebuggerWaveformAPI`.
    - lib/
      - src/: The common CRUD api list here, probably we want to use this with the rohd debugger
        - models/
          - data.dart
          - metadata.dart
          - module_structure.dart
          - module.dart
          - signal.dart
        - module_structure_api.dart: Basic api like getSignals from modules, get value from signals

  - module_structure_repository: this layer do not have business logic but it combines public API into APIs that provide business value. This layer help abstract data acquisition from the rest of the application. It allows us to change where/how data being stored without affecting other parts of the app.
    - lib/
      - src/: The intermediary between data and presenter. Allow user to inject any of the dependency through constructor and access it from presenter.
```

## Important Widget for BLOC

- BlocBuilder: Flutter widget which requires a Bloc and a builder function. BlocBuilder handles building the widget in response to new states.
- BlocProvider: Flutter widget which provides a bloc to its children via `BlocProvider.of<T>(context)`.
- BlocListener:  Flutter widget which takes a BlocWidgetListener and an **optional** Bloc and invokes the listener in response to state changes in the bloc.
- BlocConsumer: BlocConsumer exposes a builder and listener in order to react to new states. BlocConsumer is analogous to a nested BlocListener and BlocBuilder but reduces the amount of boilerplate needed.

## References

<https://bloclibrary.dev/>

----------------

Copyright (C) 2023 Intel Corporation  
SPDX-License-Identifier: BSD-3-Clause
