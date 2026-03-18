import sys
import xml.etree.ElementTree as ET
import json

def convert_cppcheck_to_sarif(xml_path, output_path):
    try:
        tree = ET.parse(xml_path)
        root = tree.getroot()
    except Exception as e:
        sys.stderr.write(f"Failed to parse cppcheck XML: {e}\n")
        return

    results = []
    errors = root.find('errors')
    if errors is not None:
        for error in errors.findall('error'):
            msg = error.get('msg', 'Unknown cppcheck error')
            rule_id = error.get('id', 'cppcheck-unknown')
            severity = error.get('severity', 'warning')
            
            # map cppcheck severity to sarif
            level = "warning"
            if severity == "error":
                level = "error"
            elif severity in ("style", "performance", "portability", "information"):
                level = "note"

            for location in error.findall('location'):
                file_path = location.get('file', '')
                if file_path.startswith('/code/'):
                    file_path = file_path[6:]
                line = int(location.get('line', 1))
                
                results.append({
                    "ruleId": f"cppcheck/{rule_id}",
                    "level": level,
                    "message": {"text": msg},
                    "locations": [{
                        "physicalLocation": {
                            "artifactLocation": {"uri": file_path},
                            "region": {
                                "startLine": line,
                                "startColumn": int(location.get('column', 1))
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
                    "name": "cppcheck",
                    "informationUri": "https://cppcheck.sourceforge.io/"
                }
            },
            "results": results
        }]
    }

    with open(output_path, 'w') as f:
        json.dump(sarif, f, indent=2)

if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("Usage: python3 cppcheck_to_sarif.py <input.xml> <output.sarif>")
    convert_cppcheck_to_sarif(sys.argv[1], sys.argv[2])
