import 'dart:convert';
import 'dart:io';

void main() {
  checkDependencies();

  print("Enter JSON file path:");
  String? filePath = stdin.readLineSync()?.trim();

  if (filePath == null || filePath.isEmpty) {
    print("Error: No file path provided.");
    return;
  }

  File file = File(filePath);

  if (!file.existsSync()) {
    print("Error: File not found at $filePath");
    return;
  }

  try {
    String jsonString = file.readAsStringSync().trim();
    jsonString = jsonString.replaceAll(': null', ': ""'); // Replace null with empty string
    Map<String, dynamic> jsonData = jsonDecode(jsonString);

    // Validate the JSON before processing
    validateJson(jsonData);

    print("Enter module name:");
    String? module = stdin.readLineSync()?.trim();

    if (module == null || module.isEmpty) {
      print("Module name is mandatory!");
      return;
    }

    print("Do you want to maintain a parent folder? (y/n)");
    String? maintainParentFolder = stdin.readLineSync()?.trim().toLowerCase();
    bool useParentFolder = maintainParentFolder == 'y';
    String folderName = '';

    if (useParentFolder) {
      print("Enter folder name:");
      folderName = stdin.readLineSync()?.trim() ?? '';

      if (folderName.isEmpty) {
        print("Folder name cannot be empty!");
        return;
      }
    }

    processJson(module, folderName, jsonData, useParentFolder);

    // Run build_runner after generating files
    runBuildRunner();
  } catch (e) {
    print("Error parsing JSON: $e");
  }
}

void runBuildRunner() async {
  print("\nRunning build_runner...");

  try {
    // Start the build_runner process
    Process process = await Process.start(
      'flutter',
      ['pub', 'run', 'build_runner', 'watch', '--delete-conflicting-outputs'],
      runInShell: true,
    );

    // Listen to stdout and stderr streams and print them in real-time
    process.stdout.transform(utf8.decoder).listen((data) {
      stdout.write(data);
    });

    process.stderr.transform(utf8.decoder).listen((data) {
      stderr.write(data);
    });

    // Wait for the process to complete
    int exitCode = await process.exitCode;

    if (exitCode != 0) {
      print("❌ Build Runner failed with exit code $exitCode.");
    } else {
      print("✅ Build completed successfully!");
    }
  } catch (e) {
    print("❌ Error running build_runner: $e");
  }
}

void checkDependencies() {
  File pubspecFile = File("pubspec.yaml");
  if (!pubspecFile.existsSync()) {
    print(
        "Error: pubspec.yaml not found! Run this script inside a Flutter project.");
    exit(1);
  }

  // Define dependencies and their versions
  Map<String, String> dependencies = {
    "freezed_annotation": "^3.0.0",
  };

  Map<String, String> devDependencies = {
    "freezed": "^3.0.4",
    "build_runner": "^2.4.15",
    "json_serializable": "^6.9.4",
  };

  List<String> missingDeps = [];
  List<String> missingDevDeps = [];

  List<String> lines = pubspecFile.readAsLinesSync();

  // Check for missing dependencies
  dependencies.forEach((dep, version) {
    if (!lines.any((line) => line.trim().startsWith("$dep:"))) {
      missingDeps.add("$dep: $version");
    }
  });

  // Check for missing dev_dependencies
  devDependencies.forEach((dep, version) {
    if (!lines.any((line) => line.trim().startsWith("$dep:"))) {
      missingDevDeps.add("$dep: $version");
    }
  });

  if (missingDeps.isNotEmpty || missingDevDeps.isNotEmpty) {
    print("\nThe following dependencies are missing:");
    if (missingDeps.isNotEmpty) {
      print("Dependencies: ${missingDeps.join(', ')}");
    }
    if (missingDevDeps.isNotEmpty) {
      print("Dev Dependencies: ${missingDevDeps.join(', ')}");
    }

    print("\nDo you want to add them? (y/n)");
    String? response = stdin.readLineSync();
    if (response?.toLowerCase() == 'y') {
      // Add missing dependencies
      if (missingDeps.isNotEmpty) {
        for (var dep in missingDeps) {
          Process.runSync('flutter',
              ['pub', 'add', dep.split(':').first, '--sdk', 'flutter']);
        }
      }

      // Add missing dev_dependencies
      if (missingDevDeps.isNotEmpty) {
        for (var devDep in missingDevDeps) {
          Process.runSync(
              'flutter', ['pub', 'add', devDep.split(':').first, '--dev']);
        }
      }

      print("Dependencies added successfully.");
    } else {
      print("Skipping dependency installation.");
    }
  } else {
    print("All required dependencies are already installed.");
  }
}

void processJson(String module, String folderName,
    Map<String, dynamic> jsonData, bool useParentFolder) {
  String pascalFolderName =
      toPascalCase(folderName.isEmpty ? module : folderName);
  String infrastructurePath =
      "lib/infrastructure/$module/${useParentFolder ? '$folderName/' : ''}";
  String domainPath =
      "lib/domain/$module/${useParentFolder ? '$folderName/' : ''}";

  Directory(infrastructurePath).createSync(recursive: true);
  Directory(domainPath).createSync(recursive: true);

  generateDtoFile(module, folderName, pascalFolderName, jsonData,
      infrastructurePath, domainPath, useParentFolder);
}

void generateDtoFile(
  String module,
  String folderName,
  String pascalFolderName,
  Map<String, dynamic> jsonData,
  String infraPath,
  String domainPath,
  bool useParentFolder,
) {
  String projectName = getProjectName(); // Dynamically get the project name
  String lowerCaseFolderName =
      folderName.isEmpty ? module.toLowerCase() : folderName.toLowerCase();
  String dtoFilePath = "$infraPath${lowerCaseFolderName}_dto.dart";
  String entityFilePath = "$domainPath${lowerCaseFolderName}.dart";

  List<String> imports = [];
  jsonData.forEach((key, value) {
    String childName = toPascalCase(key); // Convert key to PascalCase for class name
    String childFileName = childName.toLowerCase(); // Convert key to lowercase for file name

    if (value is List) {
      // Handle lists with null or empty elements
      if (value.isNotEmpty && value.first != null && value.first is Map) {
        try {
          generateDtoFile(module, childFileName, childName, value.first as Map<String, dynamic>, 
                          infraPath, domainPath, useParentFolder);
          imports.add(
              "import 'package:$projectName/infrastructure/$module/${useParentFolder ? '$folderName/' : ''}${childFileName}_dto.dart';");
        } catch (e) {
          print("Warning: Failed to process list item for key: $key. Error: $e");
          // Add a comment instead of an import
          imports.add("// Failed to process list item for key: $key");
        }
      } else {
        // Handle lists with null or primitive elements
        imports.add("// Skipping child DTO generation for key: $key (list with null or primitive elements)");
      }
    } else if (value is Map && (value as Map).isNotEmpty) {
      // Recursively generate child DTOs for non-empty maps
      try {
        generateDtoFile(module, childFileName, childName, value as Map<String, dynamic>, 
                        infraPath, domainPath, useParentFolder);
        imports.add(
            "import 'package:$projectName/infrastructure/$module/${useParentFolder ? '$folderName/' : ''}${childFileName}_dto.dart';");
      } catch (e) {
        print("Warning: Failed to process map for key: $key. Error: $e");
        // Add a comment instead of an import
        imports.add("// Failed to process map for key: $key");
      }
    } else if (value is Map) {
      // Handle empty maps
      imports.add("// Skipping child DTO generation for key: $key (empty map)");
    }
  });

  print("Generating DTO: $dtoFilePath...");
  File(dtoFilePath).writeAsStringSync(generateDtoContent(module, folderName, pascalFolderName, jsonData, imports, useParentFolder));

  print("Generating Entity: $entityFilePath...");
  File(entityFilePath).writeAsStringSync(generateEntityContent(module, folderName, pascalFolderName, jsonData, imports, useParentFolder));

  print("✅ DTO and entity files created successfully!");
}

String generateDtoContent(
    String module,
    String folderName,
    String pascalFolderName,
    Map<String, dynamic> jsonData,
    List<String> imports,
    bool useParentFolder) {
  StringBuffer buffer = StringBuffer();
  String projectName = getProjectName(); // Get the project name dynamically
  buffer
      .writeln("import 'package:freezed_annotation/freezed_annotation.dart';");

  // If folderName is empty, use module name as the folder name
  String actualFolderName = folderName.isEmpty ? module : folderName;

  // Ensure correct domain import without an extra folder when no parent folder is used
  if (useParentFolder) {
    buffer.writeln(
        "import 'package:$projectName/domain/$module/$actualFolderName/$actualFolderName.dart';");
  } else {
    buffer.writeln(
        "import 'package:$projectName/domain/$module/$actualFolderName.dart';");
  }

  // Ensure DTO imports from `infrastructure`
  imports = imports.map((import) {
    return import
        .replaceAll("package:$projectName/", "package:$projectName/")
        .replaceAll(".dart';", "_dto.dart';") // Ensure correct DTO import
        .replaceAll("_dto_dto.dart", "_dto.dart"); // Fix duplicate `_dto_dto`
  }).toList();

  imports.forEach(buffer.writeln);

  buffer.writeln("");
  buffer.writeln("part '${actualFolderName}_dto.freezed.dart';");
  buffer.writeln("part '${actualFolderName}_dto.g.dart';");
  buffer.writeln("");
  buffer.writeln("@freezed");
  buffer
      .writeln("class ${pascalFolderName}DTO with _\$${pascalFolderName}DTO {");
  buffer.writeln("  const ${pascalFolderName}DTO._();");
  buffer.writeln(" const factory ${pascalFolderName}DTO({");

  jsonData.forEach((key, value) {
    String variableName = toCamelCase(
        key.startsWith('_') ? key.substring(1) : key); // Convert to camelCase

    if (value is Map) {
      // Objects are non-nullable and use @Default
      buffer.writeln("    @Default(${toPascalCase(variableName)}DTO.empty)");
      buffer.writeln(
          "    @JsonKey(name: '$key') ${toPascalCase(variableName)}DTO $variableName,");
    } else if (value is List) {
      // Lists are required and non-nullable
      buffer.writeln(
          "    @JsonKey(name: '$key', defaultValue: <${getListType(variableName, value, isDto: true)}>[]) required List<${getListType(variableName, value, isDto: true)}> $variableName,");
    } else {
      // Primitives are required and non-nullable
      buffer.writeln(
          "    @JsonKey(name: '$key', defaultValue: ${getDefaultValue(variableName, value)}) required ${getDartType(variableName, value, isDto: true)} $variableName,");
    }
  });

  buffer.writeln("  }) = _${pascalFolderName}DTO;");
  buffer.writeln("");
  buffer.writeln(
      "  factory ${pascalFolderName}DTO.fromJson(Map<String, dynamic> json) =>");
  buffer.writeln("      _\$${pascalFolderName}DTOFromJson(json);");
  buffer.writeln("");
  buffer.writeln("  static const empty = ${pascalFolderName}DTO(");

  jsonData.forEach((key, value) {
    String variableName = toCamelCase(
        key.startsWith('_') ? key.substring(1) : key); // Convert to camelCase

    if (value is Map) {
      // Assign the `empty` constructor of the nested DTO
      buffer.writeln("    $variableName: ${toPascalCase(variableName)}DTO.empty,");
    } else if (value is List) {
      // Assign an empty list for lists
      buffer.writeln(
          "    $variableName: <${getListType(variableName, value, isDto: true)}>[],");
    } else {
      // Assign default values for primitives
      buffer.writeln(
          "    $variableName: ${getDefaultValue(variableName, value)},");
    }
  });

  buffer.writeln("  );");
  buffer.writeln("");
  buffer.writeln("  ${pascalFolderName} toDomain() => ${pascalFolderName}(");

  jsonData.forEach((key, value) {
    String variableName = toCamelCase(
        key.startsWith('_') ? key.substring(1) : key); // Convert to camelCase

    if (value is List && (value.isEmpty || !(value.first is Map))) {
      // Directly assign the list if it's empty or not a list of objects
      buffer.writeln("    $variableName: $variableName,");
    } else if (value is List) {
      // Map the list to .toDomain() if it's a list of objects
      buffer.writeln(
          "    $variableName: $variableName.map((e) => e.toDomain()).toList(),");
    } else if (value is Map) {
      buffer.writeln("    $variableName: $variableName.toDomain(),");
    } else {
      buffer.writeln("    $variableName: $variableName,");
    }
  });

  buffer.writeln("  );");
  buffer.writeln("}");
  return buffer.toString();
}

String generateEntityContent(
    String module,
    String folderName,
    String pascalFolderName,
    Map<String, dynamic> jsonData,
    List<String> imports,
    bool useParentFolder) {
  StringBuffer buffer = StringBuffer();
  String projectName = getProjectName(); // Dynamically get the project name
  String lowerCaseFolderName =
      folderName.isEmpty ? module.toLowerCase() : folderName.toLowerCase();

  buffer
      .writeln("import 'package:freezed_annotation/freezed_annotation.dart';");

  // Ensure entity imports from `domain`, not `infrastructure`
  imports = imports.map((import) {
    return import
        .replaceAll("package:$projectName/infrastructure/",
            "package:$projectName/domain/")
        .replaceAll(
            "_dto.dart';", ".dart';"); // Convert DTO imports to entity imports
  }).toList();

  imports.forEach(buffer.writeln);

  buffer.writeln("");
  buffer.writeln("part '${lowerCaseFolderName}.freezed.dart';");
  buffer.writeln("");
  buffer.writeln("@freezed");
  buffer.writeln("class $pascalFolderName with _\$$pascalFolderName {");
  buffer.writeln("  const $pascalFolderName._();");
  buffer.writeln("  const factory $pascalFolderName({");

  jsonData.forEach((key, value) {
    String variableName = toCamelCase(key.startsWith('_')
        ? key.substring(1)
        : key); // Remove leading underscore for variable name
    buffer.writeln(
        "    required ${getDartType(variableName, value, isDto: false)} $variableName,");
  });

  buffer.writeln("  }) = _$pascalFolderName;");
  buffer.writeln("");
  buffer.writeln(
      "  factory $pascalFolderName.empty() => const $pascalFolderName(");

  jsonData.forEach((key, value) {
    String variableName = toCamelCase(key.startsWith('_')
        ? key.substring(1)
        : key); // Remove leading underscore for variable name

    if (value is List) {
      buffer.writeln(
          "    $variableName: <${getListType(variableName, value, isDto: false)}>[],");
    } else if (value is Map) {
      buffer
          .writeln("    $variableName: ${toPascalCase(variableName)}.empty(),");
    } else {
      buffer.writeln(
          "    $variableName: ${getDefaultValue(variableName, value)},");
    }
  });

  buffer.writeln("  );");
  buffer.writeln("}");
  return buffer.toString();
}

String getDefaultValue(String key, dynamic value) {
  if (value == null) {
    return "null"; // Use `null` as the default value for nullable fields
  }
  if (value is List) {
    return isPrimitiveList(value)
        ? "<${getListType(key, value, isDto: false)}>[]"
        : "<${toPascalCase(key)}DTO>[]";
  }
  if (value is Map) return "${toPascalCase(key)}DTO.empty";
  if (value is int) return "0";
  if (value is double) return "0.0";
  if (value is bool) return "false";
  return "''"; // Default to an empty string for other types
}

String getDartType(String key, dynamic value, {required bool isDto}) {
  if (value is int) return "int";
  if (value is double) return "double";
  if (value is bool) return "bool";
  if (value is List) {
    return "List<${getListType(key, value, isDto: isDto)}>";
  }
  if (value is Map) return "${toPascalCase(key)}${isDto ? 'DTO' : ''}";
  return "String";
}

bool isPrimitiveList(List<dynamic> value) {
  if (value.isEmpty) return true;
  
  // Check if all elements are primitive or null
  return value.every((item) =>
      item == null ||
      item is String ||
      item is int ||
      item is double ||
      item is bool);
}

String toPascalCase(String text) {
  return text
      .split(RegExp(r'[_\s-]')) // Split by underscores, spaces, or hyphens
      .map((word) => word.isNotEmpty
          ? word[0].toUpperCase() + word.substring(1).toLowerCase()
          : '')
      .join();
}

String toCamelCase(String text) {
  if (text.isEmpty) return text;

  // Split the text by underscores, spaces, or hyphens
  List<String> words = text.split(RegExp(r'[_\s-]'));

  // Convert the first word to lowercase and capitalize the rest
  return words.first.toLowerCase() +
      words
          .skip(1)
          .map((word) => word.isNotEmpty
              ? word[0].toUpperCase() + word.substring(1).toLowerCase()
              : '')
          .join();
}

String getListType(String key, List<dynamic> value, {required bool isDto}) {
  // Check if the list is empty
  if (value.isEmpty) {
    return "dynamic"; // Default to `dynamic` for empty lists
  }

  // Find the first non-null element
  dynamic firstNonNull;
  try {
    firstNonNull = value.firstWhere((item) => item != null, orElse: () => null);
  } catch (e) {
    // Handle error and return a default type
    return "dynamic";
  }

  // If all elements are null or firstNonNull is still null
  if (firstNonNull == null) {
    return "dynamic"; // Default to `dynamic` for lists with all null elements
  }

  if (firstNonNull is Map) {
    // Generate a DTO for the list items if isDto is true, otherwise use the entity
    return "${toPascalCase(key)}${isDto ? 'DTO' : ''}";
  }
  if (firstNonNull is String) {
    return "String";
  }
  if (firstNonNull is int) {
    return "int";
  }
  if (firstNonNull is double) {
    return "double";
  }
  if (firstNonNull is bool) {
    return "bool";
  }
  return "dynamic"; // Default to `dynamic` for unknown types
}

bool isNestedObject(dynamic value) {
  if (value is Map) return true;
  if (value is List && value.isNotEmpty) {
    // Safely check if the first element is a Map
    try {
      return value.first is Map;
    } catch (e) {
      return false;
    }
  }
  return false;
}

String getProjectName() {
  File pubspecFile = File("pubspec.yaml");
  if (!pubspecFile.existsSync()) {
    throw Exception(
        "Error: pubspec.yaml not found! Run this script inside a Flutter project.");
  }

  List<String> lines = pubspecFile.readAsLinesSync();
  for (String line in lines) {
    if (line.startsWith("name:")) {
      return line.split(":")[1].trim();
    }
  }

  throw Exception("Error: Project name not found in pubspec.yaml.");
}

void validateJson(Map<String, dynamic> jsonData) {
  jsonData.forEach((key, value) {
    if (value == null) {
      print("Warning: Key '$key' has a null value. Providing a default value.");
    }
    if (value is List && value.isEmpty) {
      print("Warning: Key '$key' has an empty list.");
    }
    if (value is Map) {
      // Recursively validate nested objects
      validateJson(value as Map<String, dynamic>);
    } else if (value is List) {
      // Recursively validate nested lists
      for (var item in value) {
        if (item is Map) {
          validateJson(item as Map<String, dynamic>);
        }
      }
    }
  });
}