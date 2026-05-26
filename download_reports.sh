#!/usr/bin/env bash
# Download all FRS reports as JSON into ./reports/. Safe to re-run (skips existing files).

API="https://frs.systems.gov.bt/api/v1"
DZONGKHAGS="1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20"
GEWOG_YEARS="2024 2025 2026"
FROM=2000
TO=2027

# log in
EMAIL="${FRS_EMAIL:-}"; PASSWORD="${FRS_PASSWORD:-}"
[ -z "$EMAIL" ]    && read -r -p "FRS email: " EMAIL
[ -z "$PASSWORD" ] && { read -r -s -p "FRS password: " PASSWORD; echo; }
curl -s "$API/users/sign_in" -H "Content-Type: application/json" \
  -d "{\"user\":{\"login\":\"$EMAIL\",\"password\":\"$PASSWORD\"}}" -c cookies.txt >/dev/null
grep -q _frs_key cookies.txt || { echo "Login failed"; exit 1; }
echo "Logged in."

# download one file (skip if we already have it), printing progress
COUNT=0
fetch() {
  [ -s "$2" ] && return
  COUNT=$((COUNT + 1))
  echo "[$COUNT] $2"
  curl -s "$1" -b cookies.txt -o "$2"
}

# list the category id numbers for a domain
categories() {
  curl -s "$API/product_categories?categories[]=$1&per_page=200" -b cookies.txt \
    | grep -oE '"id":[0-9]+' | grep -oE '[0-9]+'
}

# dzongkhag report (year range): endpoint, category-filter, name
dl_dzongkhag() {
  mkdir -p "reports/${3}_dzongkhag"
  for cat in $(categories "$2"); do
    for dz in $DZONGKHAGS; do
      fetch "$API/$1/years?dzongkhag_id=$dz&product_category_id=$cat&from_year=$FROM&to_year=$TO" \
            "reports/${3}_dzongkhag/${3}_dz${dz}_cat${cat}.json"
    done
  done
  echo "$3 dzongkhag done"
}

# gewog report: endpoint, category-filter, name, mode (year|noyear)
dl_gewog() {
  mkdir -p "reports/${3}_gewog"
  for cat in $(categories "$2"); do
    for dz in $DZONGKHAGS; do
      if [ "$4" = "year" ]; then
        for y in $GEWOG_YEARS; do
          fetch "$API/$1/gewogs?dzongkhag_id=$dz&product_category_id=$cat&year=$y" \
                "reports/${3}_gewog/${3}_dz${dz}_cat${cat}_y${y}.json"
        done
      else
        fetch "$API/$1/gewogs?dzongkhag_id=$dz&product_category_id=$cat" \
              "reports/${3}_gewog/${3}_dz${dz}_cat${cat}.json"
      fi
    done
  done
  echo "$3 gewog done"
}

# reports with both levels
dl_dzongkhag crop_reports                crop             crop
dl_gewog     crop_reports                crop             crop           year
dl_dzongkhag input_supply_reports        input_supply     input_supply
dl_gewog     input_supply_reports        input_supply     input_supply   noyear
dl_dzongkhag machinery_reports           machinery        machinery
dl_gewog     machinery_reports           machinery        machinery      year
dl_dzongkhag land_reports                land_development land
dl_gewog     land_reports                land_development land           year
dl_dzongkhag infrastructure_reports      chiwog_infra     infrastructure
dl_gewog     infrastructure_reports      chiwog_infra     infrastructure year
dl_dzongkhag forecast_production_reports crop             forecast
dl_gewog     forecast_production_reports crop             forecast       noyear

# irrigation (dzongkhag only)
mkdir -p reports/irrigation_dzongkhag
for cat in $(categories irrigation); do
  for dz in $DZONGKHAGS; do
    fetch "$API/irrigation_reports/dzongkhags?product_category_id=$cat&selected_dzongkhag_ids[]=$dz" \
          "reports/irrigation_dzongkhag/irrigation_dz${dz}_cat${cat}.json"
  done
done
echo "irrigation done"

# farmer (no category)
mkdir -p reports/farmer
fetch "$API/farmer_reports" "reports/farmer/overall.json"
for dz in $DZONGKHAGS; do
  fetch "$API/farmer_reports/registered?dzongkhag_id=$dz"                              "reports/farmer/registered_dz${dz}.json"
  fetch "$API/farmer_land_reports?land_type=Chhuzhing&dzongkhag_id=$dz"                "reports/farmer/land_dz${dz}.json"
  fetch "$API/farmer_land_reports/mechanization?land_type=Chhuzhing&dzongkhag_id=$dz"  "reports/farmer/land_mechanized_dz${dz}.json"
done
echo "farmer done"

echo "Finished: $(find reports -type f | wc -l) files in ./reports/"
