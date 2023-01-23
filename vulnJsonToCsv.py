# Below is a script to parse JSON into CSV to list vuln data
# the JSON is fetched using the following 3 API calls:
# lacework api post /api/v2/Vulnerabilities/Hosts/search -d '{ "timeFilter": { "startTime": "2023-01-13T20:30:00Z", "endTime": "2023-01-15T22:30:00Z"}, "filters": [ { "field": "severity", "expression": "eq", "value": "Critical" } ], "returns": [ "mid", "severity", "status", "vulnId", "evalCtx", "fixInfo", "featureKey", "machineTags", "cveProps" ] }' >> vuln-criticals.json
# lacework api post /api/v2/Vulnerabilities/Hosts/search -d '{ "timeFilter": { "startTime": "2023-01-13T20:30:00Z", "endTime": "2023-01-15T22:30:00Z"}, "filters": [ { "field": "severity", "expression": "eq", "value": "High" } ], "returns": [ "mid", "severity", "status", "vulnId", "evalCtx", "fixInfo", "featureKey", "machineTags", "cveProps" ] }' >> vuln-highs.json
# lacework api post /api/v2/Vulnerabilities/Hosts/search -d '{ "timeFilter": { "startTime": "2023-01-13T20:30:00Z", "endTime": "2023-01-15T22:30:00Z"}, "filters": [ { "field": "severity", "expression": "eq", "value": "Medium" } ], "returns": [ "mid", "severity", "status", "vulnId", "evalCtx", "fixInfo", "featureKey", "machineTags", "cveProps" ] }' >> vuln-mediums.json



import json
import csv

with open('vuln-criticals.json') as json_file:
    data = json.load(json_file)
 
dataData = data.get('data')

vuln_scan_csv = open('vuln-criticals.csv', 'w')
csv_writer = csv.writer(vuln_scan_csv)
fields = ['CVE ID', 'Severity', 'Status', 'Instance ID', 'Hostname', 'CVE Description', 'AWS Account']
csv_writer.writerow(fields)

count = 0
for n in dataData:
    print(str(count))

    vulnId = dataData[count]['vulnId']
    print(vulnId)

    severity = dataData[count]['severity']
    print(severity)

    status = dataData[count]['status']
    print(status)

    machineTags = dataData[count]['machineTags']
    InstanceId = machineTags.get('InstanceId')
    print(InstanceId)
    
    Hostname = machineTags.get('Hostname')
    print(Hostname)

    Account = machineTags.get('Account')
    print(Account)

    cveProps = dataData[count]['cveProps']
    description = cveProps.get('description')
    print(description)

    row = [vulnId, severity, status, InstanceId, Hostname, description, Account]
    csv_writer.writerow(row)

    count +=1

vuln_scan_csv.close()


