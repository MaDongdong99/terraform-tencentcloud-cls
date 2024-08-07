locals {
  logsets = { for k, logset in var.logsets: k => logset if try(logset.create, true)}
  topics = flatten([
    for k, logset in var.logsets: [
      for topic_k, topic in logset.topics: merge(topic, {
        logset_k: k,
        topic_k: format("%s_%s", k, topic_k)
      }) if try(topic.create, true)
    ]
  ])
  topic_map = { for topic in local.topics: topic.topic_k => topic}
  indices = { for topic_k, topic in local.topic_map: topic_k => try(topic.idx, {}) if try(topic.create_index, false)}
  user_uids = {
    for user in data.tencentcloud_cam_users.all.user_list: user.name => user.uid
  }
  alarm_notice_ids = {
    for k, alarm_notice in tencentcloud_cls_alarm_notice.alarm_notice: k => alarm_notice.id
  }
}

resource "tencentcloud_cls_logset" "logset" {
  for_each = local.logsets
  logset_name   = each.value.logset_name
  tags          = merge(var.tags, try(each.value.logset_tags, {}))
}

resource "tencentcloud_cls_topic" "topics" {
  for_each = local.topic_map
  logset_id             = tencentcloud_cls_logset.logset[each.value.logset_k].id
  topic_name            = try(each.value.topic_name, each.key)
  describes = try(each.value.describes, null)
  auto_split            = try(each.value.auto_split, true) // Whether to enable automatic split. Default value: true.
  max_split_partitions  = try(each.value.max_split_partitions, 50) // Maximum number of partitions to split into for this topic if automatic split is enabled. Default value: 50.
  partition_count = try(each.value.partition_count, 1) // Number of log topic partitions. Default value: 1. Maximum value: 10.
  period                = try(each.value.period, 30) // Lifecycle in days. Value range: 1~366. Default value: 30.
  hot_period = try(each.value.hot_period, 0) // 0: Turn off log sinking. Non 0: The number of days of standard storage after enabling log settling. HotPeriod needs to be greater than or equal to 7 and less than Period. Only effective when StorageType is hot.
  storage_type = try(each.value.storage_type, "hot") // Log topic storage class. Valid values: hot: real-time storage; cold: offline storage. Default value: hot. If cold is passed in, please contact the customer service to add the log topic to the allowlist first..
  tags                  = try(var.tags, try(each.value.topic_tags, {}))
}

resource "tencentcloud_cls_index" "indices" {
  for_each = local.indices
  topic_id = tencentcloud_cls_topic.topics[each.key].id
  include_internal_fields = try(each.value.include_internal_fields, false) // Internal field marker of full-text index. Default value: false. Valid value: false: excluding internal fields; true: including internal fields.
  metadata_flag = try(each.value.metadata_flag, 0) // Metadata flag. Default value: 0. Valid value: 0: full-text index (including the metadata field with key-value index enabled); 1: full-text index (including all metadata fields); 2: full-text index (excluding metadata fields)..
  status = try(each.value.status, true) //  Whether to take effect. Default value: true.
  dynamic "rule"{
    for_each = try(each.value.rule, [])
    content {
      dynamic "dynamic_index" {
        for_each = lookup(rule.value, "dynamic_index", [])
        content {
          status = try(dynamic_index.value.status, false)
        }
      }

      dynamic "full_text" {
        for_each = lookup(rule.value,"full_text",[] )
        content {
          case_sensitive = full_text.value.case_sensitive
          tokenizer = lookup(full_text.value, "tokenizer", null)
          contain_z_h = lookup(full_text.value,"contain_z_h", true)
        }
      }

      dynamic "key_value"{
        for_each = lookup(rule.value,"key_value",[] )
        content {
          case_sensitive = key_value.value.case_sensitive

          dynamic "key_values"{
            for_each = lookup(key_value.value, "key_values", [])
            content {
              key = key_values.value.key
              dynamic "value" {
                for_each = lookup(key_values.value,"value",[] )
                content {
                  type = value.value.type
                  tokenizer = lookup(value.value,"tokenizer","" )
                  sql_flag = lookup(value.value,"sql_flag",null )
                  contain_z_h = lookup(value.value,"contain_z_h",null )
                }
              }
            }
          }
        }
      }
      dynamic "tag"{
        for_each = lookup(rule.value,"tag",[] )
        content {
          case_sensitive = tag.value.case_sensitive

          dynamic "key_values"{
            for_each = lookup(tag.value, "key_values", [])
            content {
              key = key_values.value.key
              dynamic "value"{
                for_each = lookup(key_values.value,"value",[] )
                content {
                  type = value.value.type
                  tokenizer = lookup(value.value,"tokenizer","" )
                  sql_flag = lookup(value.value,"sql_flag",null )
                  contain_z_h = lookup(value.value,"contain_z_h",null )
                }
              }
            }
          }
        }
      }
    }
  }
}


resource "tencentcloud_cls_alarm" "alarm" {
  for_each = var.alarms
  name = each.value.name
  alarm_notice_ids = concat(try(each.value.alarm_notice_ids, []), [ for alarm_notice_key in try(each.value.alarm_notices, []): local.alarm_notice_ids[alarm_notice_key]])
  alarm_period     = try(each.value.alarm_period, 15)
  condition        = try(each.value.condition, null) # "test"
  message_template = "{{.Label}}"
  status           = try(each.value.status, true)
  tags = var.tags
  trigger_count = 1

  dynamic alarm_targets {
    for_each = try(each.value.targets, [])
    content {
      end_time_offset   = 0
      logset_id         = try(tencentcloud_cls_logset.logset[alarm_targets.value.logset_key].id, alarm_targets.value.logset_key)
      number            = try(alarm_targets.value.number, 1)
      query             = alarm_targets.value.query
      start_time_offset = alarm_targets.value.start_time_offset
      topic_id          = try(tencentcloud_cls_topic.topics[format("%s_%s", alarm_targets.value.logset_key, alarm_targets.value.topic_key)].id, alarm_targets.value.topic_key)
      syntax_rule       = try(alarm_targets.value.syntax_rule, 1)
    }
  }

  dynamic analysis {
    for_each = try(each.value.analysis, [])
    content {
      content = try(analysis.value.content, "__FILENAME__")
      name    = analysis.value.name
      type    = try(analysis.value.type, "field")

      dynamic config_info {
        for_each = try(analysis.value.config_info, [])
        content {
          key   = config_info.value.key # "QueryIndex"
          value = config_info.value.value #"1"
        }
      }
    }
  }

  monitor_time {
    time = try(each.value.monitor_time.time, 1)
    type = try(each.value.monitor_time.type, "Period")
  }
  lifecycle {
    ignore_changes = [
      condition  # this field always updated because it is not synced from api
    ]
  }
}

data "tencentcloud_cam_users" "all" {
  #  depends_on = [tencentcloud_cam_user.users]
}

resource "tencentcloud_cls_alarm_notice" "alarm_notice" {
  for_each = var.alarm_notices
  name = each.value.name
  tags = var.tags
  type = try(each.value.type, "All") #  Trigger - Alarm triggered, Recovery - Alarm recovery All - Alarm triggered and alarm recovery

  dynamic notice_receivers {
    for_each = try(each.value.notice_receivers, {})
    content {
      index = notice_receivers.value.index
      receiver_channels = try(notice_receivers.value.receiver_channels, [
        "Sms",
      ])
      receiver_ids = concat(try(notice_receivers.value.receiver_ids, []),  [ for user in try(notice_receivers.value.receivers, []): local.user_uids[user]])
      receiver_type = try(notice_receivers.value.receiver_type ,"Uin")
      start_time    = try(notice_receivers.value.start_time , "00:00:00")
      end_time      = try(notice_receivers.value.end_time , "23:59:59")
    }
  }
}


resource "tencentcloud_cls_data_transform" "data_transform" {
  for_each = var.data_transforms
  func_type    = each.value.func_type
  src_topic_id = tencentcloud_cls_topic.topics[format("%s_%s", each.value.src_logset, each.value.src_topic)].id # tencentcloud_cls_topic.topic_src.id
  name         = each.value.name # "iac-test-src"
  etl_content  = each.value.etl_content # "ext_sep(\"content\", \"f1, f2, f3\", sep=\",\", quote=\"\", restrict=False, mode=\"overwrite\")fields_drop(\"content\")"
  task_type    = each.value.task_type # 3
  enable_flag  = each.value.enable_flag # 1
  dynamic dst_resources {
    for_each = try(each.value.dst_resources, [])
    content {
      topic_id = tencentcloud_cls_topic.topics[format("%s_%s", dst_resources.value.dst_logset, dst_resources.value.dst_topic)].id # tencentcloud_cls_topic.topic_dst.id
      alias    = try(dst_resources.value.alias, "")
    }
  }
  lifecycle {
#    ignore_changes = [
#      etl_content # this can not be changed
#    ]
  }
}