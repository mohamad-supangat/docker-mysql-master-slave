#!/bin/bash

docker-compose down -v
sudo rm -rf ./master/data/*
sudo rm -rf ./slave/data/*
docker-compose build
docker-compose up -d

until docker exec mysql_master sh -c 'export MYSQL_PWD=111; mysql -u root -e ";"'; do
    echo "Waiting for mysql_master database connection..."
    sleep 4
done

# buat user di master
priv_stmt='CREATE USER "mydb_slave_user"@"%" IDENTIFIED BY "mydb_slave_pwd"; GRANT REPLICATION SLAVE ON *.* TO "mydb_slave_user"@"%"; FLUSH PRIVILEGES;'
docker exec mysql_master sh -c "export MYSQL_PWD=111; mysql -u root -e '$priv_stmt'"

until docker-compose exec mysql_slave sh -c 'export MYSQL_PWD=111; mysql -u root -e ";"'; do
    echo "Waiting for mysql_slave database connection..."
    sleep 4
done

# buat user di slave
priv_stmt='CREATE USER "mydb_user"@"%" IDENTIFIED BY "mydb_pwd"; GRANT REPLICATION SLAVE ON *.* TO "mydb_user"@"%"; FLUSH PRIVILEGES;'
docker exec mysql_slave sh -c "export MYSQL_PWD=111; mysql -u root -e '$priv_stmt'"

# mysql slave to master
MS_STATUS=$(docker exec mysql_master sh -c 'export MYSQL_PWD=111; mysql -u root -e "SHOW MASTER STATUS"')
CURRENT_LOG=$(echo $MS_STATUS | awk '{print $6}')
CURRENT_POS=$(echo $MS_STATUS | awk '{print $7}')

start_slave_stmt="CHANGE MASTER TO MASTER_HOST='mysql_master',MASTER_USER='mydb_slave_user',MASTER_PASSWORD='mydb_slave_pwd',MASTER_LOG_FILE='$CURRENT_LOG',MASTER_LOG_POS=$CURRENT_POS; START SLAVE;"
start_slave_cmd='export MYSQL_PWD=111; mysql -u root -e "'
start_slave_cmd+="$start_slave_stmt"
start_slave_cmd+='"'
docker exec mysql_slave sh -c "$start_slave_cmd"

docker exec mysql_slave sh -c "export MYSQL_PWD=111; mysql -u root -e 'SHOW SLAVE STATUS \G'"

# mysql master to slave
MS_STATUS=$(docker exec mysql_slave sh -c 'export MYSQL_PWD=111; mysql -u root -e "SHOW MASTER STATUS"')
CURRENT_LOG=$(echo $MS_STATUS | awk '{print $6}')
CURRENT_POS=$(echo $MS_STATUS | awk '{print $7}')
# echo $CURRENT_LOG
start_master_stmt="CHANGE MASTER TO MASTER_HOST='mysql_slave',MASTER_USER='mydb_user',MASTER_PASSWORD='mydb_pwd',MASTER_LOG_FILE='$CURRENT_LOG',MASTER_LOG_POS=$CURRENT_POS; START SLAVE;"
start_master_cmd='export MYSQL_PWD=111; mysql -u root -e "'
start_master_cmd+="$start_master_stmt"
start_master_cmd+='"'
docker exec mysql_master sh -c "$start_master_cmd"

docker exec mysql_master sh -c "export MYSQL_PWD=111; mysql -u root -e 'SHOW SLAVE STATUS \G'"
