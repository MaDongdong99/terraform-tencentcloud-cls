locals {
  tags = {
    create: "terraform"
  }
  notice_receiver = "receiver1@abc.xyz"
}

resource "tencentcloud_cam_user" "users" {
  name                = local.notice_receiver
  remark              = local.notice_receiver
  console_login       = true
  use_api             = true
  need_reset_password = true
  force_delete        = true
}

module "cls" {
  depends_on = [ tencentcloud_cam_user.users ]
  source = "../.."
  logsets = {
    logset1 = {
      logset_name = "logset1"
      topics = {
        topic1 = {
          topic_name = "topic1"
          describes = "topic1"
          auto_split = true
          max_split_partitions = 50
          partition_count      = 1
          period               = 30
          hot_period = 15
          storage_type         = "hot"
          tags                 = merge(local.tags, {})
          create_index = true
          idx = {
            rule = [{
              dynamic_index = [{
                status = false
              }
              ]
              full_text = [{
                tokenizer      = "@&()='\",;:<>[]{}/ \n\t\r"
                case_sensitive = false
                contain_z_h    = false
              }]
              key_value = [
                {
                  case_sensitive = false
                  key_values = [
                    {
                      key = "__CONTENT__"
                      value = [{
                        contain_z_h = true
                        sql_flag    = true
                        tokenizer   = "@&?|#()='\",;:<>[]{}/ \n\t\r\\"
                        type        = "text"
                      }]
                    }
                  ]
                }
              ]
              tag = [
                {
                  case_sensitive = false
                  key_values = [
                    {
                      key = "namespace"
                      value = [{
                        contain_z_h = false
                        sql_flag    = false
                        tokenizer   = "@&()='\",;:<>[]{}/ \n\t\r"
                        type        = "text"
                      }]
                    },
                    {
                      key = "pod_name"
                      value = [{
                        contain_z_h = false
                        sql_flag    = true
                        tokenizer   = "@&()='\",;:<>[]{}/ \n\t\r"
                        type        = "text"
                      }]
                    },
                    {
                      key = "container_name"

                      value = [{
                        contain_z_h = false
                        sql_flag    = false
                        tokenizer   = "@&()='\",;:<>[]{}/ \n\t\r"
                        type        = "text"
                      }]

                    }
                  ]
                }
              ]
            }]

            status                  = true
            include_internal_fields = false
            metadata_flag           = 0
          }
        }
      }
    }
    logset2 = {
      logset_name = "logset2"
      topics = {
        topic2 = {
          topic_name = "topic2"
          describes = "topic2"
          auto_split = true
          max_split_partitions = 50
          partition_count      = 1
          period               = 30
          hot_period = 15
          storage_type         = "hot"
          tags                 = merge(local.tags, {})
        }
      }
    }
  }
  alarm_notices = {
    group1: {
      name : "group1"
      notice_receivers: {
        "1": {
          index : 1
          receivers : [local.notice_receiver]
          receiver_channels : ["Email"]
          type : "Trigger"
        }
      }
    }
  }
  alarms = {
    alarm1: {
      name: "alarm1"
      alarm_period: 5
      alarm_notices: [
        "group1"
      ]
      condition: "[$1.__QUERYCOUNT__]> 50"
      targets: [
        {
          logset_key: "logset1"
          topic_key: "topic1"
          query: "\"Exception\""
          start_time_offset : -5
        }
      ]
      analysis: [
        {
          content: "*"
          name: "Exception"
          type: "original"
          config_info: [
            {
              key : "Fields"
              value : "__CONTENT__"
            },
            {
              key : "QueryIndex"
              value : "1"
            },
            {
              key : "Format"
              value : "1"
            },
            {
              key  : "Limit"
              value : "1"
            }
          ]
        }
      ]
      monitor_time: {
        time : 5
      }
    }
  }

  data_transforms = {
    dt1 = {
      func_type: 1
      src_logset: "logset1"
      src_topic: "topic1"
      name: "monitoring"
      etl_content: "log_drop(regex_match(v(\"__CONTENT__\"),regex=\"^(?!.*exception).*$\",full=False))\nfields_drop(\"__CONTENT__\")"
      task_type: 3
      enable_flag: 1
      dst_resources: [
        {
          dst_logset : "logset2"
          dst_topic : "topic2"
          alias : "monitoring_output"
        }
      ]
    }
  }
}