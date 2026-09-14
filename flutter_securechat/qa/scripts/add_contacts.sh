#!/usr/bin/env bash
# QA test kisileri ekler. Ad'lar acikca "QA Test" onekli, silinmeleri kolay olsun.
set -uo pipefail
SC_SERIAL="${SC_SERIAL:-$(adb devices | awk 'NR>1 && $2=="device"{print $1; exit}')}"
a() { adb -s "$SC_SERIAL" shell "$@"; }

add() {
  local name="$1" phone="$2"
  a content insert --uri content://com.android.contacts/raw_contacts \
      --bind account_name:s:qa_test --bind account_type:s:qa.test >/dev/null 2>&1
  local rid
  rid=$(a "content query --uri content://com.android.contacts/raw_contacts --projection _id --sort '_id DESC'" \
        2>/dev/null | head -1 | grep -oE '_id=[0-9]+' | cut -d= -f2)
  [ -z "$rid" ] && { echo "raw_contact olusturulamadi: $name"; return 1; }
  a content insert --uri content://com.android.contacts/data \
      --bind raw_contact_id:i:"$rid" \
      --bind mimetype:s:vnd.android.cursor.item/name \
      --bind data1:s:"$name" >/dev/null 2>&1
  a content insert --uri content://com.android.contacts/data \
      --bind raw_contact_id:i:"$rid" \
      --bind mimetype:s:vnd.android.cursor.item/phone_v2 \
      --bind data1:s:"$phone" --bind data2:i:2 >/dev/null 2>&1
  echo "eklendi: $name $phone (raw_contact_id=$rid)"
}

add "QA Test Ayse" "+905550000001"
add "QA Test Mehmet" "+905550000002"

echo "--- rehberdeki QA kayitlari ---"
a "content query --uri content://com.android.contacts/data --projection data1 --where \"mimetype='vnd.android.cursor.item/phone_v2'\"" 2>/dev/null
