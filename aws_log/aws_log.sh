#!/usr/bin/env bash
set -euo pipefail

# Usage: ./run_audit_queries.sh INPUT_CSV OUTPUT_CSV LOG_GROUP_NAME
#
# Example:
#   ./run_audit_queries.sh queries.csv results.csv "/aws/rds/instance/mydb/audit"

if [[ $# -lt 3 ]]; then
  echo "Usage: $0 INPUT_CSV OUTPUT_CSV LOG_GROUP_NAME" >&2
  exit 1
fi

INPUT_CSV="$1"
OUTPUT_CSV="$2"
LOG_GROUP_NAME="$3"

# Dependencies: aws cli, jq, GNU date (on macOS you might need gdate from coreutils)
command -v aws >/dev/null 2>&1 || { echo "aws CLI not found" >&2; exit 1; }
command -v jq  >/dev/null 2>&1 || { echo "jq not found" >&2; exit 1; }
command -v date >/dev/null 2>&1 || { echo "date not found" >&2; exit 1; }

# Read header to get SQL column names
header_line="$(head -n1 "$INPUT_CSV")"
IFS=',' read -r -a HEADERS <<< "$header_line"

# Output header for result CSV
echo 'input_datetime,buffer_seconds,query_column,query,event_timestamp,event_message' > "$OUTPUT_CSV"

# Process each data row
tail -n +2 "$INPUT_CSV" | while IFS= read -r line; do
  # Skip blank lines
  [[ -z "$line" ]] && continue

  # Split row into columns
  IFS=',' read -r -a cols <<< "$line"

  datetime="${cols[0]}"
  buffer="${cols[1]:-0}"   # default 0 seconds if empty

  # Convert datetime to epoch seconds
  # If you're on macOS and using gdate, replace `date` with `gdate` here.
  ts="$(date -d "$datetime" +%s)"

  # Calculate start/end in milliseconds (CloudWatch Logs expects ms)
  start_ms=$(( (ts - buffer) * 1000 ))
  end_ms=$(( (ts + buffer) * 1000 ))

  # For each SQL column (everything after the first two columns)
  for (( i=2; i<${#cols[@]}; i++ )); do
    sql="${cols[$i]}"

    # Skip empty SQL cells
    [[ -z "$sql" ]] && continue

    query_col_name="${HEADERS[$i]}"

    # Call AWS Logs; adjust filter-pattern to match your log format.
    # Here we just search the raw SQL string.
    # aws logs filter-log-events \
    #   --log-group-name "$LOG_GROUP_NAME" \
    #   --start-time "$start_ms" \
    #   --end-time "$end_ms" \
    #   --filter-pattern "$sql" \
    #   --query 'events[].{timestamp:timestamp,message:message}' \
    #   --output json |
    # jq -r \
    #   --arg dt "$datetime" \
    #   --arg buf "$buffer" \
    #   --arg qcol "$query_col_name" \
    #   --arg sql "$sql" \
    #   '
    #   .[] |
    #   [
    #     $dt,
    #     $buf,
    #     $qcol,
    #     $sql,
    #     (.timestamp | tostring),
    #     .message
    #   ] | @csv
    #   ' >> "$OUTPUT_CSV"

    aws logs filter-log-events \
      --log-group-name "$LOG_GROUP_NAME" \
      --start-time "$start_ms" \
      --end-time "$end_ms" \
      --filter-pattern "$sql" \
      --query 'events[].{timestamp:timestamp,message:message}' \
      --output json |
    jq -r '
      .[] |
      [
        (.timestamp | tostring),
        .message
      ] | @csv
    ' >> "$OUTPUT_CSV"

  done
done
