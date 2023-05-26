#!/usr/bin/env bash
DB_BACKUP_PATH=/data/
CURRENT_DATE=$(date +%F_%T)
echo "Dump mysql db for $DB_NAME... "
mysql --version

IGNORE=""
for table in $IGNORE_TABLES; do
  IGNORE+="--ignore-table=$DB_NAME.$table "
done

if test -n "${ONLY_TABLE-}"; then
 echo "🚧 Creating backup only for table $ONLY_TABLE"
 SQL="SET group_concat_max_len = 10240;"
 SQL="${SQL} SELECT GROUP_CONCAT(table_name separator ' ')"
 SQL="${SQL} FROM information_schema.tables WHERE table_schema='${DB_NAME}'"
 SQL="${SQL} AND table_name LIKE '$ONLY_TABLE'"
 echo $SQL
 TBLIST=`mysql -h "$DB_HOST" -u $DB_USER -p"$DB_PASS" -AN -e"${SQL}"`
 
 mysqldump -h "$DB_HOST" -u $DB_USER -p"$DB_PASS" $DB_NAME $TBLIST --verbose > $DB_BACKUP_PATH/$DB_NAME-$CURRENT_DATE.sql
elif [[ "${IGNORE_TABLES}" ]]; then
 echo "🚧 Ignoring table $IGNORE_TABLES"
 mysqldump -h "$DB_HOST" -u $DB_USER -p"$DB_PASS" $DB_NAME $IGNORE --verbose > $DB_BACKUP_PATH/$DB_NAME-$CURRENT_DATE-2.sql
 echo "🚧 Uploading mysql dump ($DB_NAME-$CURRENT_DATE.sql) to s3 ..."
 aws s3 --endpoint=https://$S3_URL cp $DB_BACKUP_PATH/$DB_NAME-$CURRENT_DATE-2.sql s3://${S3_BUCKET}/db/
else
 echo "✅Creating backup for entire database"
 mysqldump -h "$DB_HOST" -u $DB_USER -p"$DB_PASS" $DB_NAME --verbose  | gzip > $DB_BACKUP_PATH/$DB_NAME-$CURRENT_DATE-90.sql.gz
 echo "🚧 Uploading mysql dump ($DB_NAME-$CURRENT_DATE.sql) to s3 ..."
 aws s3 --endpoint=https://$S3_URL cp $DB_BACKUP_PATH/$DB_NAME-$CURRENT_DATE-90.sql s3://${S3_BUCKET}/db/
fi


echo "✅ Backup finished successfully"

deleted="false"
echo "⚠️ Check for files older than X days ..."

cd /data
currentDate=$(date +%s)

aws s3 --endpoint=https://$S3_URL ls $S3_BUCKET/db/ | while read -r line; do
  fileName=$(echo $line | awk '{print $4}')
  createdAt=$(echo "$line" | awk '{print $4}' | awk -F'[-_.]' '{print $2"-"$3"-"$4" "$5}')
  createdAt=$(date -d "$createdAt" +%s)
  fileAge=$(( ($currentDate - $createdAt) / (24*60*60) ))

  # Extract the number of days from the file name
  fileAgeFromName=$(echo $fileName | awk -F'[-.]' '{print $(NF-1)}')

  # Check if the file is older than the specified number of days
  if [[ $fileAge -gt $fileAgeFromName ]]; then
    deleted="true"
    echo "🚨 Deleting file $fileName"
    aws s3 --endpoint=https://$S3_URL rm s3://$S3_BUCKET/db/$fileName
  fi
done

if [[ $deleted == "false" ]]; then
  echo "✅ Nothing to delete"
fi

echo "👋 Bye"
