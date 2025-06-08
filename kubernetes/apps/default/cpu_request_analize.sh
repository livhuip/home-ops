#!/bin/bash

NODE_NAME=${1:-"talos-cp-02"}

echo "=== DETAILED RESOURCE INVESTIGATION FOR $NODE_NAME ==="
echo

echo "� 1. CURRENT PODS ON NODE:"
kubectl get pods --all-namespaces --field-selector spec.nodeName=$NODE_NAME -o wide

echo
echo "�️ 2. ROOK-CEPH COMPONENTS ANALYSIS:"
echo "--- All Rook Ceph Pods ---"
kubectl get pods -n rook-ceph -o wide
kubectl get pods -n rook-ceph-external -o wide

echo
echo "--- Rook Ceph Resource Requests ---"
kubectl get pods -n rook-ceph -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].resources.requests.cpu}{"\t"}{.spec.containers[*].resources.requests.memory}{"\n"}{end}' | column -t

echo
echo "--- Rook Ceph External Resource Requests ---"
kubectl get pods -n rook-ceph-external -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].resources.requests.cpu}{"\t"}{.spec.containers[*].resources.requests.memory}{"\n"}{end}' | column -t

echo
echo "� 3. ACTUAL CPU USAGE vs REQUESTS:"
echo "--- Current CPU Usage ---"
kubectl top pods --all-namespaces --sort-by=cpu | grep -E "(rook-ceph|$NODE_NAME)" | head -10

echo
echo "� 4. ROOK CEPH CLUSTER CONFIGURATION:"
echo "--- CephCluster Resource Specs ---"
kubectl get cephcluster -n rook-ceph -o yaml | grep -A 20 -B 5 "resources:"

echo
echo "--- CephCluster MON/OSD Settings ---"
kubectl get cephcluster -n rook-ceph -o jsonpath='{.items[*].spec.mon}' | jq '.'
kubectl get cephcluster -n rook-ceph -o jsonpath='{.items[*].spec.storage}' | jq '.'

echo
echo "� 5. NODE CAPACITY CHECK:"
kubectl describe node $NODE_NAME | grep -A 10 "Capacity:"

echo
echo "� 6. SPECIFIC HIGH-CPU CONSUMERS:"
echo "Looking for pods with >500m CPU requests..."

kubectl get pods --all-namespaces --field-selector spec.nodeName=$NODE_NAME -o json | \
jq -r '.items[] | select(.spec.containers[]?.resources.requests.cpu != null) | 
{
  namespace: .metadata.namespace,
  name: .metadata.name,
  cpu_requests: [.spec.containers[]?.resources.requests.cpu // "0m"],
  total_cpu: ([.spec.containers[]?.resources.requests.cpu // "0m"] | map(rtrimstr("m") | if . == "" then 0 else tonumber end) | add)
} | 
select(.total_cpu > 500) |
"\(.namespace)/\(.name): \(.total_cpu)m (\(.cpu_requests | join(", ")))"'