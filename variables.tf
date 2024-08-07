variable "logsets" {
  type = any
  default = {}
}

variable "tags" {
  type = map(string)
  default = {}
}

variable "alarms" {
  type = any
  default = {}
}

variable "alarm_notices" {
  type = any
  default = {}
}

variable "data_transforms" {
  type = any
  default = {}
}
