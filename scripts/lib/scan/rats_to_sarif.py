import sys
import xml.etree.ElementTree as ET
import json

def convert_rats_to_sarif(xml_path, output_path):
    try:
        tree = ET.parse(xml_path)
        root = tree.getroot()
    except Exception as e:
        sys.stderr.write(f"Failed to parse rats XML: {e}\n")
        return

    results = []
    for vuln in root.findall('vulnerability'):
        severity = vuln.findtext('severity', 'High')
        type_str = vuln.findtext('type', 'Unknown')
        message = vuln.findtext('message', 'No message provided')

        level = "warning"
        if severity == "High":
            level = "error"

        for file_node in vuln.findall('file'):
            file_name = file_node.findtext('name', '')
            for line_node in file_node.findall('line'):
                line = int(line_node.text or 1)
                
                results.append({
                    "ruleId": f"rats/{type_str}",
                    "level": level,
                    "message": {"text": message},
                    "locations": [{
                        "physicalLocation": {
                            "artifactLocation": {"uri": file_name},
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
                    "name": "rats",
                    "informationUri": "https://github.com/andrew-d/rough-auditing-tool-for-security"
                }
            },
            "results": results
        }]
    }

    with open(output_path, 'w') as f:
        json.dump(sarif, f, indent=2)

if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("Usage: python3 rats_to_sarif.py <input.xml> <output.sarif>")
    convert_rats_to_sarif(sys.argv[1], sys.argv[2])
