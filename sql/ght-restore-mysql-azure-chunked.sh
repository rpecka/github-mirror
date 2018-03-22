#!/usr/bin/env bash

# defaults
user="ghtorrent"
passwd=""
host="localhost"
db="ghtorrent"
engine="InnoDB"
splitDir="split-dir"

usage()
{
  echo "Usage: $0 [-u dbuser ] [-p dbpasswd ] [-h dbhost] [-d database ] [-s splitDir] dump_dir"
  echo
  echo "Restore a database from CSV and SQL files in dump_dir"
  echo "    -u database user (default: $user)"
  echo "    -p database passwd (default: $passwd)"
  echo "    -h database host (default: $host)"
  echo "    -d database to restore to. Must exist. (default: $db)"
  echo "    -e db engine: InnoDB for normal operations (default: $engine)"
  echo "                  MyISAM for fast import and querying speed"
  echo "     -s the name of the directory where splits will be generated"
  echo "                  All contents of this directory will be deleted"
}

if [ -z $1 ]
then
  usage
  exit 1
fi

while getopts "u:p:h:d:e:" o
do
  case $o in
  u)  user=$OPTARG ;;
  p)  passwd=$OPTARG ;;
  h)  host=$OPTARG ;;
  d)  db=$OPTARG ;;
  e)  engine=$OPTARG ;;
  s)  splitDir=$OPTARG
  \?)     echo "Invalid option: -$OPTARG" >&2
    usage
    exit 1
    ;;
  esac
done

# Setup MySQL command line
if [ -z $passwd ]; then
  mysql="mysql -u $user -s -h $host -D $db"
else
  mysql="mysql -u $user --password=$passwd -s -h $host -D $db"
fi

shift $(expr $OPTIND - 1)
dumpDir=$1

if [ ! -e $dumpDir ]; then
  echo "Cannot find directory to restore from"
  exit 1
fi

# Convert to full path
dumpDir="`pwd`/$dumpDir"

if [ ! -e $dumpDir/schema.sql ]; then
  echo "Cannot find $dumpDir/schema.sql to create DB schema"
  exit 1
fi

# 1. Create db schema
echo "`date` Creating the DB schema"
cat $dumpDir/schema.sql |
sed -e "s/\`ghtorrent\`/\`$db\`/" |
sed -e "s/InnoDB/$engine/"|
grep -v "^--" |
$mysql

# 2. Restore CSV files with disabled FK checks
for f in $dumpDir/*.csv ; do
  echo "`date` Removing split directory: $splitDir"
  rm -rf "$splitDir"
  echo "`date` Removed split directory"

  echo "Creating new split directory"
  mkdir "$splitDir"

  echo "Copying $f to $splitDir"
  cp "$f $splitDir"
  echo "Done copying $f to splitDir"

  echo "Splitting $f in $splitDir"
  split -l 500000 -d "$f $f"
  echo "Done splitting $f in $splitDir"

  echo "Removing $f from $splitDir"
  rm -rf "$splitDir/$f"
  echo "Removed $f from $splitDir"

  for s in $splitDir/*.csv* ; do
  	table=`basename $f|cut -f1 -d'.'`
  echo "`date` Restoring table $table"

  # Make sure to use LOAD DATA LOCAL in the following command because other loads are not permitted by azure
  echo "SET foreign_key_checks = 0; LOAD DATA LOCAL INFILE '$s' INTO TABLE $table CHARACTER SET UTF8 FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '\"' LINES TERMINATED BY '\n' " |$mysql || exit 1
  done

done

# 3. Create indexes
if [ ! -e $dumpDir/indexes.sql ]; then
  echo "Cannot find $dumpDir/indexes.sql to create DB indexes"
  exit 1
fi

echo "`date` Creating indexes"
cat $dumpDir/indexes.sql |
sed -e "s/\`ghtorrent\`/\`$db\`/" |
grep -v "^--" |
while read idx; do
  echo "`date` $idx"
  echo $idx | $mysql || exit 1
done

#: ft=bash