output "services" {
  description = "Service names created by the app module."
  value = {
    ingest  = module.svc_ingest_api.name
    results = module.svc_results_api.name
    qa      = module.svc_qa_web.name
    redis   = module.svc_redis.name
  }
}

output "pvcs" {
  value = {
    sub_pc_frames = module.pvc_sub_pc_frames.name
    pc_frames     = module.pvc_pc_frames.name
    segments      = module.pvc_segments.name
  }
}

output "deployments" {
  value = {
    ingest_api   = module.dep_ingest_api.name
    results_api  = module.dep_results_api.name
    qa_web       = module.dep_qa_web.name
    convert_ply  = module.dep_convert_ply.name
    part_labeler = module.dep_part_labeler.name
    redactor     = module.dep_redactor.name
    analytics    = module.dep_analytics.name
    redis        = module.dep_redis.name
  }
}
