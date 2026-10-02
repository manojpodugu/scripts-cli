#!/bin/bash

OUTPUT="/root/oci_block_volume_inventory.csv"
SNO=1

TENANCY_ID=$(grep '^tenancy=' /root/.oci/config | cut -d'=' -f2 | tr -d '\r')

echo "S.No,Name,Size,State,Status,OCID,Compartment Name,Region Name" > "$OUTPUT"

REGIONS=$(oci iam region-subscription list \
  --query 'data[]."region-name"' \
  --output json | jq -r '.[]')

COMPARTMENTS=$(oci iam compartment list \
  --compartment-id "$TENANCY_ID" \
  --compartment-id-in-subtree true \
  --access-level ACCESSIBLE \
  --all \
  --output json | jq -r '.data[].id')

# Add root tenancy
COMPARTMENTS="$TENANCY_ID"$'\n'"$COMPARTMENTS"

for REGION in $REGIONS
do
    echo "Processing region: $REGION"

    while IFS= read -r COMPARTMENT_ID
    do
        [ -z "$COMPARTMENT_ID" ] && continue

        COMPARTMENT_NAME=$(oci iam compartment get \
          --compartment-id "$COMPARTMENT_ID" \
          --region "$REGION" \
          --query 'data.name' \
          --raw-output 2>/dev/null)

        [ -z "$COMPARTMENT_NAME" ] && continue

        echo "  Compartment: $COMPARTMENT_NAME"

        VOLUMES=$(oci bv volume list \
          --compartment-id "$COMPARTMENT_ID" \
          --region "$REGION" \
          --all \
          --output json 2>/dev/null)

        if ! echo "$VOLUMES" | jq empty >/dev/null 2>&1; then
            continue
        fi

        while IFS= read -r VOLUME
        do
            [ -z "$VOLUME" ] && continue

            NAME=$(echo "$VOLUME" | jq -r '."display-name" // "Unknown"')

            SIZE=$(echo "$VOLUME" | jq -r '."size-in-gbs" // "0"')

            STATE=$(echo "$VOLUME" | jq -r '."lifecycle-state" // "Unknown"')

            VOLUME_OCID=$(echo "$VOLUME" | jq -r '.id')

            ATTACHMENTS=$(oci compute volume-attachment list \
              --compartment-id "$COMPARTMENT_ID" \
              --volume-id "$VOLUME_OCID" \
              --region "$REGION" \
              --output json 2>/dev/null)

            ATTACHMENT_COUNT=$(echo "$ATTACHMENTS" |
              jq -r '.data | length' 2>/dev/null)

            if [[ "$ATTACHMENT_COUNT" =~ ^[0-9]+$ ]] &&
               [ "$ATTACHMENT_COUNT" -gt 0 ]; then
                STATUS="Attached"
            else
                STATUS="Not-Attached"
            fi

            printf '%s,"%s",%s,%s,%s,%s,"%s",%s\n' \
              "$SNO" \
              "$NAME" \
              "$SIZE" \
              "$STATE" \
              "$STATUS" \
              "$VOLUME_OCID" \
              "$COMPARTMENT_NAME" \
              "$REGION" >> "$OUTPUT"

            SNO=$((SNO + 1))

        done < <(echo "$VOLUMES" | jq -c '.data[]' 2>/dev/null)

    done <<< "$COMPARTMENTS"

done

TOTAL_VOLUMES=$((SNO - 1))

echo "" >> "$OUTPUT"
echo "Overall Block Volume Count,$TOTAL_VOLUMES" >> "$OUTPUT"

echo
echo "Inventory completed."
echo "Total block volumes: $TOTAL_VOLUMES"
echo "Output file: $OUTPUT"
