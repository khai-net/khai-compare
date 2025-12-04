# KHAI Compare - Analysis Tool

C program for analyzing comparison data between control (T-) and treated (T+) collections.

## Input Format

The program expects a JSON input file with the following structure:

```json
{
  "controlCollection": "collection_name_for_control",
  "treatedCollection": "collection_name_for_treated",
  "markerName": "optional_marker_name"
}
```

### Fields:
- **controlCollection** (required): MongoDB collection name for the control (T-) clone
- **treatedCollection** (required): MongoDB collection name for the treated (T+) clone
- **markerName** (optional): Name of the marker to use for filtering analysis

## Building

### Prerequisites
- GCC compiler
- Third-party libraries (libbson, libzstd, libmongoc)

### Setup Third-Party Libraries

The project uses statically linked third-party libraries. You need to build them first:

1. Copy the `build-third-party.sh` script from KHAI-Net to this directory
2. Run the build script:
```bash
./build-third-party.sh
```

This will create a `third-party/` directory with all required libraries.

### Compile
```bash
make
```

## Usage

```bash
./khai-compare <input_json_file> [output_json_file]
```

### Example:
```bash
./khai-compare sample_input.json output.json
```

### Test:
```bash
make test
```

## Next Steps

The current implementation provides the JSON parsing structure. You need to add:

1. **MongoDB Connection**: Connect to MongoDB to fetch data from the specified collections
2. **Data Retrieval**: Extract the Qua fields from documents in both collections
3. **Marker Filtering**: If a marker is provided, filter the data based on marker items
4. **Analysis Logic**: Implement your comparison/analysis algorithms
5. **Output Generation**: Generate comprehensive JSON output with analysis results

## Code Structure

```c
typedef struct {
    char *control_collection;
    char *treated_collection;
    char *marker_name;
    int has_marker;
} AnalysisInput;
```

The `parse_input_file()` function handles all JSON parsing and returns a populated `AnalysisInput` structure.

## Cleanup

```bash
make clean
```
