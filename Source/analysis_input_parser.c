#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <bson/bson.h>
#include "analysis_input_parser.h"

/**
 * Free the analysis input structure
 */
void free_analysis_input(AnalysisInput *input) {
    if (input->control_collection) {
        free(input->control_collection);
    }
    if (input->treated_collection) {
        free(input->treated_collection);
    }
    if (input->marker_name) {
        free(input->marker_name);
    }
}

/**
 * Parse the JSON input file
 */
int parse_input_file(const char *filename, AnalysisInput *input) {
    FILE *file = fopen(filename, "r");
    if (!file) {
        fprintf(stderr, "Error: Cannot open input file '%s'\n", filename);
        return -1;
    }

    // Read file content
    fseek(file, 0, SEEK_END);
    long file_size = ftell(file);
    fseek(file, 0, SEEK_SET);

    char *json_content = malloc(file_size + 1);
    if (!json_content) {
        fprintf(stderr, "Error: Memory allocation failed\n");
        fclose(file);
        return -1;
    }

    fread(json_content, 1, file_size, file);
    json_content[file_size] = '\0';
    fclose(file);

    // Parse JSON with BSON
    bson_error_t error;
    bson_t *bson = bson_new_from_json((const uint8_t *)json_content, file_size, &error);
    free(json_content);

    if (!bson) {
        fprintf(stderr, "Error: Failed to parse JSON: %s\n", error.message);
        return -1;
    }

    // Extract control collection
    bson_iter_t iter;
    if (!bson_iter_init_find(&iter, bson, "controlCollection") ||
        !BSON_ITER_HOLDS_UTF8(&iter)) {
        fprintf(stderr, "Error: Missing or invalid 'controlCollection' field\n");
        bson_destroy(bson);
        return -1;
    }
    input->control_collection = strdup(bson_iter_utf8(&iter, NULL));

    // Extract treated collection
    if (!bson_iter_init_find(&iter, bson, "treatedCollection") ||
        !BSON_ITER_HOLDS_UTF8(&iter)) {
        fprintf(stderr, "Error: Missing or invalid 'treatedCollection' field\n");
        bson_destroy(bson);
        free(input->control_collection);
        return -1;
    }
    input->treated_collection = strdup(bson_iter_utf8(&iter, NULL));

    // Extract marker name (optional)
    if (bson_iter_init_find(&iter, bson, "markerName") &&
        BSON_ITER_HOLDS_UTF8(&iter)) {
        const char *marker = bson_iter_utf8(&iter, NULL);
        if (marker && strlen(marker) > 0) {
            input->marker_name = strdup(marker);
            input->has_marker = 1;
        } else {
            input->marker_name = NULL;
            input->has_marker = 0;
        }
    } else {
        input->marker_name = NULL;
        input->has_marker = 0;
    }

    bson_destroy(bson);
    return 0;
}

/**
 * Main function
 */
int main(int argc, char *argv[]) {
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <input_json_file> [output_json_file]\n", argv[0]);
        return 1;
    }

    const char *input_file = argv[1];
    const char *output_file = argc > 2 ? argv[2] : "output.json";

    // Parse input
    AnalysisInput input = {0};
    if (parse_input_file(input_file, &input) != 0) {
        return 1;
    }

    // Print parsed data
    printf("Control Collection: %s\n", input.control_collection);
    printf("Treated Collection: %s\n", input.treated_collection);
    if (input.has_marker) {
        printf("Marker Name: %s\n", input.marker_name);
    } else {
        printf("Marker Name: (none)\n");
    }

    // TODO: Implement your analysis logic here
    // 1. Connect to MongoDB and fetch data from collections
    // 2. Apply marker filtering if marker is provided
    // 3. Perform comparison/analysis
    // 4. Write results to output_file

    // Create output BSON (placeholder)
    bson_t *output = bson_new();
    BSON_APPEND_UTF8(output, "status", "success");
    BSON_APPEND_UTF8(output, "controlCollection", input.control_collection);
    BSON_APPEND_UTF8(output, "treatedCollection", input.treated_collection);

    if (input.has_marker) {
        BSON_APPEND_UTF8(output, "markerName", input.marker_name);
    }

    // Write output as JSON
    char *output_string = bson_as_canonical_extended_json(output, NULL);
    FILE *out = fopen(output_file, "w");
    if (out) {
        fprintf(out, "%s\n", output_string);
        fclose(out);
        printf("\nOutput written to: %s\n", output_file);
    }

    bson_free(output_string);
    bson_destroy(output);
    free_analysis_input(&input);

    return 0;
}
