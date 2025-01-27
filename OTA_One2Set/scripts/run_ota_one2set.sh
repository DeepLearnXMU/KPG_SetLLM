#!/bin/bash

# home_dir="/home/yjc/codes/kg_one2set"
# export PYTHONPATH=${home_dir}:${PYTHONPATH}
# export CUDA_VISIBLE_DEVICES=1

data_dir="data/kp20k_separated"

seed=27
dropout=0.1
learning_rate=0.0001
batch_size=12
copy_attention=true

max_kp_len=6
max_kp_num=20
loss_scale_pre=0.2
loss_scale_ab=0.1
set_loss=true
assign_steps=2
gpuid=$1
k_strategy="normal"
top_candidates=3
assign_temperature=10
adaptive_lr_scale=false
null_cost_zero=false
interrupt_cost=false

model_name="OTA_One2set"
data_args="Full"
main_args="Seed${seed}_TopK${top_candidates}_AT${assign_temperature}"

if [ ${copy_attention} = true ] ; then
    model_name+="_Copy"
fi
if [ "${set_loss}" = true ] ; then
    main_args+="_SetLoss"
fi
if [ "${adaptive_lr_scale}" = true ] ; then
    main_args+="_AdpLr"
fi
if [ "${null_cost_zero}" = true ] ; then
    main_args+="_NullCostZero"
fi
if [ "${interrupt_cost}" = true ] ; then
    main_args+="_IRTCost"
fi

save_data="${data_dir}/${data_args}"
mkdir -p ${save_data}

exp="${data_args}_${model_name}_${main_args}"

echo "============================= preprocess: ${save_data} ================================="

preprocess_out_dir="output/preprocess/${data_args}"
mkdir -p ${preprocess_out_dir}

cmd="python preprocess.py \
-data_dir=${data_dir} \
-save_data_dir=${save_data} \
-remove_title_eos \
-log_path=${preprocess_out_dir} \
-one2many
"

echo $cmd
eval $cmd


echo "============================= train: ${exp} ================================="

train_out_dir="output/train/${exp}/"
mkdir -p ${train_out_dir}

pretrained_model="pretrained_model/One2Set_based_model.pt"
tune_model="${train_out_dir}best_model.pt"

cp ${pretrained_model} ${tune_model}
sleep 20

if [ ! -e "$tune_model" ]; then
	echo "需要手动复制预训练的模型！" 1>&2
	exit 0
fi

cmd="python train.py \
-data ${save_data} \
-vocab ${save_data} \
-exp_path ${train_out_dir} \
-model_path=${train_out_dir} \
-learning_rate ${learning_rate} \
-one2many \
-batch_size ${batch_size} \
-seed ${seed} \
-dropout ${dropout} \
-fix_kp_num_len \
-max_kp_len ${max_kp_len} \
-max_kp_num ${max_kp_num} \
-loss_scale_pre ${loss_scale_pre} \
-loss_scale_ab ${loss_scale_ab} \
-assign_steps ${assign_steps} \
-seperate_pre_ab \
-use_optimal_transport \
-k_strategy ${k_strategy} \
-top_candidates ${top_candidates} \
-assign_temperature ${assign_temperature} \
-train_from ${tune_model} \
-gpuid ${gpuid}
"

if [ "${copy_attention}" = true ] ; then
    cmd+=" -copy_attention"
fi
if [ "${set_loss}" = true ] ; then
    cmd+=" -set_loss"
fi
if [ "${adaptive_lr_scale}" = true ] ; then
    cmd+=" -adaptive_lr_scale"
fi
if [ "${null_cost_zero}" = true ] ; then
    cmd+=" -null_cost_zero"
fi
if [ "${interrupt_cost}" = true ] ; then
    cmd+=" -interrupt_cost"
fi


echo $cmd
eval $cmd


echo "============================= test: ${exp} ================================="

#for data in "kp20k"
for data in "inspec" "krapivin" "nus" "semeval" "kp20k"
do
  echo "============================= testing ${data} ================================="
  test_out_dir="output/test/${exp}/${data}"
  mkdir -p ${test_out_dir}

  src_file="data/testsets/${data}/test_src.txt"
  trg_file="data/testsets/${data}/test_trg.txt"

  cmd="python predict.py \
  -vocab ${save_data} \
  -src_file=${src_file} \
  -pred_path ${test_out_dir} \
  -exp_path ${test_out_dir} \
  -model ${train_out_dir}/best_model.pt \
  -remove_title_eos \
  -batch_size 20 \
  -replace_unk \
  -dropout ${dropout} \
  -fix_kp_num_len \
  -one2many \
  -max_kp_len ${max_kp_len} \
  -max_kp_num ${max_kp_num} \
  -seperate_pre_ab \
  -gpuid ${gpuid}
  "
  if [ "$copy_attention" = true ] ; then
      cmd+=" -copy_attention"
  fi

  echo $cmd
  eval $cmd

  cmd="python evaluate_prediction.py \
  -pred_file_path ${test_out_dir}/predictions.txt \
  -src_file_path ${src_file} \
  -trg_file_path ${trg_file} \
  -exp_path ${test_out_dir} \
  -export_filtered_pred \
  -filtered_pred_path ${test_out_dir} \
  -disable_extra_one_word_filter \
  -invalidate_unk \
  -all_ks 5 M \
  -present_ks 5 M \
  -absent_ks 5 M
  ;cat ${test_out_dir}/results_log_5_M_5_M_5_M.txt
  "

  echo $cmd
  eval $cmd

done

