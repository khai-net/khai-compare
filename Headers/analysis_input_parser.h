#ifndef ANALYSIS_INPUT_PARSER_H
#define ANALYSIS_INPUT_PARSER_H

/**
 * Structure to hold analysis input parameters
 */
typedef struct {
    char *control_collection;   // MongoDB collection name for control (T-) clone
    char *treated_collection;   // MongoDB collection name for treated (T+) clone
    char *marker_name;          // Optional marker name for filtering
    int has_marker;             // Flag indicating if marker is present
} AnalysisInput;

/**
 * Parse the JSON input file and populate the AnalysisInput structure
 *
 * @param filename Path to the JSON input file
 * @param input Pointer to AnalysisInput structure to populate
 * @return 0 on success, -1 on error
 */
int parse_input_file(const char *filename, AnalysisInput *input);

/**
 * Free the memory allocated for an AnalysisInput structure
 *
 * @param input Pointer to AnalysisInput structure to free
 */
void free_analysis_input(AnalysisInput *input);

#endif // ANALYSIS_INPUT_PARSER_H
