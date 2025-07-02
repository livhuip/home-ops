#!/bin/bash

echo "=== Kubernetes Memory Request vs Usage Analysis ==="
echo

# Function to convert memory units to MB for comparison
convert_to_mb() {
    local value=$1
    if [[ $value =~ ^([0-9]+)Gi$ ]]; then
        echo $((${BASH_REMATCH[1]} * 1024))
    elif [[ $value =~ ^([0-9]+)Mi$ ]]; then
        echo ${BASH_REMATCH[1]}
    elif [[ $value =~ ^([0-9]+)Ki$ ]]; then
        echo $((${BASH_REMATCH[1]} / 1024))
    elif [[ $value =~ ^([0-9]+)G$ ]]; then
        echo $((${BASH_REMATCH[1]} * 1000))
    elif [[ $value =~ ^([0-9]+)M$ ]]; then
        echo ${BASH_REMATCH[1]}
    else
        echo "0"
    fi
}

echo "1. TOP MEMORY REQUESTERS (Highest to Lowest):"
echo "============================================="
kubectl get pods --all-namespaces -o json | jq -r '
.items[] | 
select(.spec.containers[]?.resources.requests.memory != null) |
{
  namespace: .metadata.namespace,
  name: .metadata.name,
  memory_request: (.spec.containers[]?.resources.requests.memory // "0Mi"),
  status: .status.phase
} | 
"\(.namespace)/\(.name) | Request: \(.memory_request) | Status: \(.status)"
' | sort -k4 -hr

echo
echo "2. CURRENT MEMORY USAGE (if metrics-server available):"
echo "======================================================"
if kubectl top pods --all-namespaces >/dev/null 2>&1; then
    kubectl top pods --all-namespaces --sort-by=memory | head -20
else
    echo "Metrics-server not available. Install it to see actual usage."
fi

echo
echo "3. PODS WITHOUT MEMORY REQUESTS (Potential Risk):"
echo "================================================="
kubectl get pods --all-namespaces -o json | jq -r '
.items[] | 
select(.spec.containers[]?.resources.requests.memory == null) |
"\(.metadata.namespace)/\(.metadata.name)"
' | head -10

echo
echo "4. NODE MEMORY ALLOCATION SUMMARY:"
echo "=================================="
kubectl describe nodes | grep -A 5 -B 1 "Allocated resources" | grep -E "(Name:|memory)"

echo
echo "5. CLUSTER MEMORY OVERVIEW:"
echo "=========================="
total_allocatable=$(kubectl get nodes -o json | jq -r '.items[].status.allocatable.memory' | sed 's/Ki$//' | awk '{sum += $1} END {print sum/1024/1024 "Gi"}')
echo "Total Allocatable Memory: $total_allocatable"

echo
echo "=== RECOMMENDATIONS ==="
echo "1. Focus on pods without memory requests (section 3)"
echo "2. Compare actual usage vs requests (sections 1 & 2)"
echo "3. Consider increasing requests for high-usage pods"
echo "4. Add memory requests to pods that don't have them"