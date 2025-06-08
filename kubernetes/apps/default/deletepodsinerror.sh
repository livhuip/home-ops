#!/bin/bash

# Pod Error State Cleanup Script
# Usage: ./cleanup_error_pods.sh [--dry-run] [--namespace <ns>]

DRY_RUN=false
NAMESPACE=""

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --namespace)
      NAMESPACE="$2"
      shift 2
      ;;
    *)
      echo "Unknown option $1"
      echo "Usage: $0 [--dry-run] [--namespace <namespace>]"
      exit 1
      ;;
  esac
done

NS_FLAG=""
if [[ -n "$NAMESPACE" ]]; then
  NS_FLAG="-n $NAMESPACE"
  echo "� Checking namespace: $NAMESPACE"
else
  NS_FLAG="--all-namespaces"
  echo "� Checking all namespaces"
fi

echo "=== POD ERROR STATE ANALYSIS ==="
echo

# Function to list pods with specific status
list_pods_with_status() {
  local status=$1
  local description=$2
  
  echo "� $description:"
  if [[ "$NAMESPACE" == "" ]]; then
    kubectl get pods --all-namespaces --field-selector=status.phase=$status --no-headers 2>/dev/null | \
    awk '{print $1 "/" $2 " (" $4 ")" }' | sort
  else
    kubectl get pods -n "$NAMESPACE" --field-selector=status.phase=$status --no-headers 2>/dev/null | \
    awk '{print "'$NAMESPACE'/" $1 " (" $3 ")" }' | sort
  fi
  echo
}

# Function to list pods by pattern
list_pods_by_pattern() {
  local pattern=$1
  local description=$2
  
  echo "� $description:"
  kubectl get pods $NS_FLAG --no-headers 2>/dev/null | grep -E "$pattern" | \
  awk '{if (NF > 5) print $1 "/" $2 " (" $4 ")"; else print $1 " (" $3 ")" }' | sort
  echo
}

# List different error states
list_pods_with_status "Failed" "Failed Pods"
list_pods_with_status "Pending" "Pending Pods"
list_pods_by_pattern "Error|CrashLoopBackOff|ImagePullBackOff|ErrImagePull|InvalidImageName" "Pods with Error Conditions"
list_pods_by_pattern "Terminating" "Pods Stuck Terminating"

# Count totals
echo "� SUMMARY:"
FAILED_COUNT=$(kubectl get pods $NS_FLAG --field-selector=status.phase=Failed --no-headers 2>/dev/null | wc -l)
PENDING_COUNT=$(kubectl get pods $NS_FLAG --field-selector=status.phase=Pending --no-headers 2>/dev/null | wc -l)
ERROR_COUNT=$(kubectl get pods $NS_FLAG --no-headers 2>/dev/null | grep -cE "Error|CrashLoopBackOff|ImagePullBackOff")

echo "- Failed pods: $FAILED_COUNT"
echo "- Pending pods: $PENDING_COUNT"
echo "- Error condition pods: $ERROR_COUNT"
echo

if [[ $FAILED_COUNT -eq 0 && $PENDING_COUNT -eq 0 && $ERROR_COUNT -eq 0 ]]; then
  echo "✅ No pods in error states found!"
  exit 0
fi

# Cleanup section
echo "� CLEANUP OPTIONS:"
echo

if [[ "$DRY_RUN" == "true" ]]; then
  echo "� DRY RUN MODE - No pods will be deleted"
  echo
  echo "Commands that would be executed:"
  echo "1. Delete failed pods:"
  echo "   kubectl delete pods $NS_FLAG --field-selector=status.phase=Failed"
  echo
  echo "2. Delete error condition pods:"
  kubectl get pods $NS_FLAG --no-headers 2>/dev/null | grep -E "Error|CrashLoopBackOff|ImagePullBackOff" | \
  while read line; do
    if [[ "$NAMESPACE" == "" ]]; then
      ns=$(echo $line | awk '{print $1}')
      pod=$(echo $line | awk '{print $2}')
      echo "   kubectl delete pod $pod -n $ns"
    else
      pod=$(echo $line | awk '{print $1}')
      echo "   kubectl delete pod $pod -n $NAMESPACE"
    fi
  done
else
  echo "⚠️  LIVE MODE - Pods will be deleted!"
  echo
  read -p "Do you want to proceed with cleanup? (y/N): " -n 1 -r
  echo
  
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "�️  Deleting failed pods..."
    kubectl delete pods $NS_FLAG --field-selector=status.phase=Failed --ignore-not-found=true
    
    echo "�️  Deleting pods with error conditions..."
    kubectl get pods $NS_FLAG --no-headers 2>/dev/null | grep -E "Error|CrashLoopBackOff|ImagePullBackOff" | \
    while read line; do
      if [[ "$NAMESPACE" == "" ]]; then
        ns=$(echo $line | awk '{print $1}')
        pod=$(echo $line | awk '{print $2}')
        echo "Deleting $pod in namespace $ns"
        kubectl delete pod $pod -n $ns --ignore-not-found=true
      else
        pod=$(echo $line | awk '{print $1}')
        echo "Deleting $pod in namespace $NAMESPACE"
        kubectl delete pod $pod -n $NAMESPACE --ignore-not-found=true
      fi
    done
    
    echo "✅ Cleanup completed!"
    echo
    echo "� Remaining pods after cleanup:"
    kubectl get pods $NS_FLAG | grep -E "Error|CrashLoopBackOff|ImagePullBackOff|Failed|Pending" || echo "No error pods remaining"
  else
    echo "❌ Cleanup cancelled"
  fi
fi

echo
echo "� TIPS:"
echo "- Use --dry-run to preview changes"
echo "- Use --namespace <ns> to limit to specific namespace"
echo "- Some pending pods might be normal (waiting for resources)"
echo "- Pods stuck in Terminating might need force deletion: kubectl delete pod <pod> --force --grace-period=0"