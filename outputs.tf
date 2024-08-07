output "logset_ids" {
  value = { for k, logset in tencentcloud_cls_logset.logset: k => logset.id }
}

output "topic_ids" {
  value = { for k, topic in tencentcloud_cls_topic.topics: k => topic.id}
}

output "index_ids" {
  value = {for k, idx in tencentcloud_cls_index.indices: k => idx.id }
}