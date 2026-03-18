import sys
import xml.etree.ElementTree as ET
import json

def convert_valgrind_to_sarif(xml_path, output_path):
    try:
        tree = ET.parse(xml_path)
        root = tree.getroot()
    except Exception as e:
        sys.stderr.write(f"Failed to parse valgrind XML: {e}\n")
        return

    results = []
    for error in root.findall('error'):
        kind = error.findtext('kind', 'UnknownValgrindError')
        what = error.findtext('what', 'Memory error detected')
        
        # Extract the first useful stack frame for location
        file_path = ""
        line = 1
        stack = error.find('stack')
        if stack is not None:
            for frame in stack.findall('frame'):
                fn = frame.findtext('fn', '')
                if fn and 'main' in fn or 'test' in fn:
                    file_path = frame.findtext('dir', '') + '/' + frame.findtext('file', '')
                    line = int(frame.findtext('line', '1') or 1)
                    break
            # Fallback to first frame if no specific function matched
            if not file_path and stack.find('frame') is not None:
                first = stack.find('frame')
                file_path = (first.findtext('dir', '') + '/' + first.findtext('file', '')).strip('/')
                line = int(first.findtext('line', '1') or 1)

        # Default to a placeholder if valgrind couldn't map the binary back to source
        if not file_path:
            file_path = "valgrind_binary_execution"
        elif file_path.startswith('/code/'):
            file_path = file_path[6:]

        results.append({
            "ruleId": f"valgrind/{kind}",
            "level": "error",
            "message": {"text": what},
            "locations": [{
                "physicalLocation": {
                    "artifactLocation": {"uri": file_path},
                    "region": {
                        "startLine": line
                    }
                }
            }]
        })

    sarif = {
        "$schema": "https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json",
        "version": "2.1.0",
        "runs": [{
            "tool": {
                "driver": {
                    "name": "valgrind",
                    "informationUri": "https://valgrind.org/"
                }
            },
            "results": results
        }]
    }

    with open(output_path, 'w') as f:
        json.dump(sarif, f, indent=2)

if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("Usage: python3 valgrind_to_sarif.py <input.xml> <output.sarif>")
    convert_valgrind_to_sarif(sys.argv[1], sys.argv[2])
