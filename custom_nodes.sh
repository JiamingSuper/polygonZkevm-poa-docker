#!/bin/bash

# 判断是否启用Docker Swarm，创建所需网络
if docker info | grep -q "Swarm: active"; then
  # 检查网络是否不存在
  if ! docker network ls --filter name=l1 -q | grep -q .; then
    docker network create --driver overlay --attachable l1
  fi
  if ! docker network ls --filter name=l2 -q | grep -q .; then
    # 创建网络
    docker network create --driver overlay --attachable l2
  fi
else
  echo "Error: Docker is not in Swarm mode."
  exit 1
fi

# 当前节点数量
node_count=$(docker node ls --format "{{.ID}}" | wc -l)

# 判断是否足够开启需要的节点数量
if ! [[ $1 =~ ^[0-9]+$ ]] || ((node_count < $1)); then
  echo "Error: There aren't enough machines or invalid input."
  echo "Please use the Docker swarm command to join enough machines."
  exit 1
fi

# 准备配置文件
if [ $1 -ge 5 ]; then
  for ((i=5; i<=$1; i++)); do
    source_folder="l2/config_n4"
    destination_folder="l2/config_n$i"
    mkdir -p "$destination_folder"
    cp -r "$source_folder"/* "$destination_folder/"
    toml_path="$destination_folder/test.node.config.toml"
    sed -i "s/l2n4/l2n$i/g" "$toml_path"
    json_path="$destination_folder/test.prover.config.json"
    sed -i "s/l2n4/l2n$i/g" "$json_path"
  done
fi

# 获取节点hostname并开启
nodes_host=($(docker node ls --format "{{.Hostname}}"))
count=0
for node in "${nodes_host[@]}"; do
    if [ $count -ge $1]; then
      break
    fi
    ((count++))
    if [ $count -eq 1 ]; then
      source_l1_file="l1_node_base.yml"
      destination_l1_file="l1/l1n1.yml"
      cp "$source_l1_file" "$destination_l1_file"
      sed -i "s/worker-006/$node/g" "$destination_l1_file"
      docker stack deploy -c "$destination_l1_file" l1
      echo "l1 RPC:  $node:8545"
      echo "l1 WS:   $node:8546"
    fi
    source_file="l2_node_base.yml"
    destination_file="l2/l2n$count.yml"
    cp "$source_file" "$destination_file"
    sed -i "s/config_n1/config_n$count/g" "$destination_file"
    sed -i "s/worker-002/$node/g" "$destination_file"
    node_port1=$((count + 8123))
    node_port2=$((count + 18133))
    sed -i "s/8123:8123/$node_port1:8123/g" "$destination_file"
    sed -i "s/8133:8133/$node_port1:8133/g" "$destination_file"
    docker stack deploy -c "$destination_file" "l2n$count"
    echo "l2n$count RPC:  $node:$node_port1"
    echo "l2n$count WS:   $node:$node_port2"
done
