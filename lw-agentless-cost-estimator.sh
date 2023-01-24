#!/bin/bash

intg_guid="$1"
time_range=86400

if [ -z "${HONEYCOMB_API_KEY}" ]; then
  echo "Please set the environment variable HONEYCOMB_API_KEY with a key that can run queries"
  exit 1
fi

if [ -z "${intg_guid}" ]; then
  echo "Usage: $0 INTG_GUID"
  exit 1
fi

echo ""
echo "********************************************************************************************************************"
echo "Calculating monthly costs for integration GUID: ${intg_guid}..."
echo "********************************************************************************************************************"
echo ""

#############################
###### General Queries ######
#############################

function getQueryId () {
	curl -s https://api.honeycomb.io/1/query_results/agentless-sidekick-prod -X POST -H "X-Honeycomb-Team: ${HONEYCOMB_API_KEY}" -d '{"query_id": "'"$1"'"}' | jq -r '.id'
}

function getResults () {
	curl -s https://api.honeycomb.io/1/query_results/agentless-sidekick-prod/"$1" -X GET -H "X-Honeycomb-Team: ${HONEYCOMB_API_KEY}"
}

##########################################################
###### Get latest scan to use in subsequent queries ######
##########################################################

function getLatestScanQuery () {
	curl -s https://api.honeycomb.io/1/queries/agentless-sidekick-prod -X POST -H "X-Honeycomb-Team: ${HONEYCOMB_API_KEY}" -d '{
	"breakdowns": ["data.checkpoint"],
	"orders": [{"column": "data.checkpoint", "order": "descending"}],
	"filters": [{ "column": "data.intg_guid", "op": "contains", "value": "'"$intg_guid"'"}, {"column": "name", "op": "=", "value": "Uploading data stream"}],
    "limit": 1,
	"time_range": '"$time_range"'
	}' | jq -r '.id'
}

latestScanQueryId=$(getLatestScanQuery)
queryIdLatestScan=$(getQueryId "$latestScanQueryId")
getLatestScan=$(getResults "$queryIdLatestScan")
latestScan=$(echo "$getLatestScan" | jq -r '.data.results | .[0] | .data."data.checkpoint"')

##############################################
###### Get Number Instances ##################
##############################################

function getNumWorkloads() {
    curl -s https://api.honeycomb.io/1/queries/agentless-sidekick-prod -X POST -H "X-Honeycomb-Team: ${HONEYCOMB_API_KEY}" -d '{
    "calculations": [{"column": "data.workload", "op": "COUNT_DISTINCT"}],
    "filters": [{ "column": "data.intg_guid", "op": "contains", "value": "'"$intg_guid"'"}, {"column": "name", "op": "=", "value": "buildfs"}, { "column": "data.checkpoint", "op": "=", "value": "'"$latestScan"'"}],
	"time_range": '"$time_range"',
    "limit": 1000
	}' | jq -r '.id'
}

getNumWorkloadsQuery=$(getNumWorkloads)
queryIdNumWorkloads=$(getQueryId "$getNumWorkloadsQuery")
getNumWorkloadsResult=$(getResults "$queryIdNumWorkloads")
numWorkloads=$(echo "$getNumWorkloadsResult" | jq -r '.data.results | .[0] | .data."COUNT_DISTINCT(data.workload)"')

######################################
###### Cost Queries ##################
######################################

function createVolumeSnapshotCost () {
    curl -s https://api.honeycomb.io/1/queries/agentless-sidekick-prod -X POST -H "X-Honeycomb-Team: ${HONEYCOMB_API_KEY}" -d '{
    "calculations": [{ "column": "data.volume_size_bytes", "op": "SUM" }],
    "filters": [{ "column": "data.intg_guid", "op": "contains", "value": "'"$intg_guid"'"}, { "column": "data.volume_size_bytes", "op": "exists"}, {"column": "name", "op": "=", "value": "Run times"}, {"column": "data.checkpoint", "op": "=", "value": "'"$latestScan"'"}],
    "time_range": '"$time_range"'
    }' | jq -r '.id'
}

function createEBSGetSnapshotBlockCallCost () {
	curl -s https://api.honeycomb.io/1/queries/agentless-sidekick-prod -X POST -H "X-Honeycomb-Team: ${HONEYCOMB_API_KEY}" -d '{
    "calculations": [{"column": "data.fetched_blocks_count", "op": "SUM"}],
	"filters": [{ "column": "data.intg_guid", "op": "contains", "value": "'"$intg_guid"'"}, {"column": "name", "op": "=", "value": "Snapshot read finished"}, {"column": "data.checkpoint", "op": "=", "value": "'"$latestScan"'"}],
	"time_range": '"$time_range"'
	}' | jq -r '.id'
}

function createECSTaskDuration () {
	curl -s https://api.honeycomb.io/1/queries/agentless-sidekick-prod -X POST -H "X-Honeycomb-Team: ${HONEYCOMB_API_KEY}" -d '{
    "calculations": [{"column": "duration_ms", "op": "SUM"}],
	"filters": [{ "column": "data.intg_guid", "op": "contains", "value": "'"$intg_guid"'"}, {"column": "name", "op": "=", "value": "buildmulti-client-wait"}, {"column": "data.checkpoint", "op": "=", "value": "'"$latestScan"'"}],
    "time_range": '"$time_range"'
	}' | jq -r '.id' 
}

function createOrchestrateDuration () {
    curl -s https://api.honeycomb.io/1/queries/agentless-sidekick-prod -X POST -H "X-Honeycomb-Team: ${HONEYCOMB_API_KEY}" -d '{
    "calculations": [{"column": "duration_ms", "op": "SUM"}],
	"filters": [{ "column": "data.intg_guid", "op": "contains", "value": "'"$intg_guid"'"}, {"column": "name", "op": "=", "value": "orchestrate-wait"}, {"column": "data.checkpoint", "op": "=", "value": "'"$latestScan"'"}],
    "time_range": '"$time_range"'
	}' | jq -r '.id' 
}

# Set first query id to a variable
volumeSnapshotCostId=$(createVolumeSnapshotCost)
EBSGetSnapshotBlockCallCostId=$(createEBSGetSnapshotBlockCallCost)
ECSTaskDurationId=$(createECSTaskDuration)
orchestrateDurationId=$(createOrchestrateDuration)

# Call getQueryId function and pass corresponding id from queries api; returns a second query id that will be used to get the query results
queryIdVolumeSnapshotCost=$(getQueryId "$volumeSnapshotCostId")
queryIdEBSGetSnapshotBlockCost=$(getQueryId "$EBSGetSnapshotBlockCallCostId")
queryIdECSTaskDuration=$(getQueryId "$ECSTaskDurationId")
queryIdOrchestrateDuration=$(getQueryId "$orchestrateDurationId")

###################################
###### PARSE AND RETURN DATA ######
###################################
NUM_INSTANCES="$numWorkloads"
COST_TOTAL=0
total_GB_Per_Scan=0

function calculateVolumeCost () {
    volumeSnapshotCostResult=$(getResults "$queryIdVolumeSnapshotCost")

    len=$(echo "$volumeSnapshotCostResult" | jq -r '.data.results | length')
    hourlyStorageRatePerGB=0.0000694
    hoursStoredPerMonth=60
    totalBytesPerScan=0  
    bytesPerGB=1073741824

    totalBytesPerScan=$(echo "$volumeSnapshotCostResult" | jq -r '.data.results[0] | .data."SUM(data.volume_size_bytes)"|tonumber')        
    gbPerScan=$(bc <<< "$totalBytesPerScan / $bytesPerGB")
    total_GB_Per_Scan="$gbPerScan"
    totalCostPerMonth=$(bc <<< "$gbPerScan * $hourlyStorageRatePerGB * $hoursStoredPerMonth")
    COST_TOTAL=$(bc <<< "$COST_TOTAL + $totalCostPerMonth")
}

function calculateCostOfAPICalls () {
    apiCallCostResult=$(getResults "$queryIdEBSGetSnapshotBlockCost")
    len=$(echo "$apiCallCostResult" | jq -r '.data.results | length')
    costPer1000Calls=0.003
    totalFetchedBlocks=$(echo "$apiCallCostResult" | jq -r '.data.results[].data."SUM(data.fetched_blocks_count)"')
    totalCostPerScan=$(bc <<< "(($totalFetchedBlocks / 1000) * $costPer1000Calls)")
    totalCostPerMonth=$(bc <<< "$totalCostPerScan * 30")

    COST_TOTAL=$(bc <<< "$COST_TOTAL + $totalCostPerMonth")
}

function calculateCostOfECSTasks () {
    ###########################
    #### Static Variables ####
    ###########################
    
    monthlyTotalCost=0
    msToHours=3600000
    #costForOneHourForOneTask = (vCPUPerHourPerTask [we have a set rate of 4CPU per task] * aws vCPU Hourly Cost (0.04656)) + (GB Per Hour Per Task [we have a set rate of 8GB] * aws GB Hourly Cost (0.00511))
    costForOneHourForOneTask=0.2212
    # averages derived from honeycomb averages
    avgGBScannedPerTask=48 
    avgSingleEcsTaskDurationHours=0.039

    ###########################
    #### Dynamic Variables ####
    ###########################

    # estimate # of tasks based on total GB per scan divided by 48 (average number of gb's scanned per task)
    numECSTasks=$(echo "$total_GB_Per_Scan / $avgGBScannedPerTask" | bc)
    # if we have results for request, utilize actual duration of ECS tasks & orchestrate
    ## Calculate duration in hours of orchestrate-wait
    orchestrateDurationResult=$(getResults "$queryIdOrchestrateDuration")
    totalOrchestrateDurationPerScan=$(echo "$orchestrateDurationResult" | jq -r '.data.results[0] | .data."SUM(duration_ms)"|tonumber')
    orchestrateDurationInHoursPerScan=$(echo "$totalOrchestrateDurationPerScan" / $msToHours | bc)

    ## Calculate duration in hours of buildmulti-client-wait
    totalECSTaskDurationResult=$(getResults "$queryIdECSTaskDuration")
    totalECSTaskDurationInMs=$(echo "$totalECSTaskDurationResult" | jq -r '.data.results[0] | .data."SUM(duration_ms)"|tonumber')
    ecsTaskDurationInHoursPerScan=$(echo "$totalECSTaskDurationInMs / $msToHours" | bc)

    totalDurationOneScan=$(echo "$ecsTaskDurationInHoursPerScan" + "$orchestrateDurationInHoursPerScan" | bc)

    if (( $ecsTaskDurationInHoursPerScan == 0 ))
    then 
        # calculate using averages
        totalCostPerScan=$(echo "$avgSingleEcsTaskDurationHours * $costForOneHourForOneTask * $numECSTasks" | bc)
        monthlyTotalCost=$(echo "$totalCostPerScan * 30" | bc)
    else 
        # calculate using data
        totalCostPerScan=$(echo "$totalDurationOneScan * $costForOneHourForOneTask" | bc)
        monthlyTotalCost=$(echo "$totalCostPerScan * 30" | bc)
    fi 

    COST_TOTAL=$(echo "$COST_TOTAL + $monthlyTotalCost" | bc)
}

function printOutput () {    
    echo ""
    echo "****************************************************"
    echo " Lacework Agentless Monthly Cost Estimator Results"
    echo "____________________________________________________"
    echo ""
    echo ""
    echo "Last Scan: " "$latestScan"
    echo ""
    echo "Number of assessed instances: " "$NUM_INSTANCES"
    echo ""
    echo "Monthly Cost Estimate: $""$COST_TOTAL"
    echo ""
    echo "**Assuming customer is scanning every 24 hours**"
    echo ""
    echo "****************************************************"
    echo ""
}

calculateVolumeCost
calculateCostOfAPICalls
calculateCostOfECSTasks
printOutput
