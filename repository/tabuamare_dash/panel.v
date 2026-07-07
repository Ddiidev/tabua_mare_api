module tabuamare_dash

import db.pg

// PanelData agrega dados para o painel do usuario (dashboard).
pub struct PanelData {
pub:
	plan_status  PlanStatus
	usage_month  UsageSummary
}

// get_panel_data retorna os dados agregados do painel para um usuario.
pub fn get_panel_data(mut db pg.DB, user_id int) !PanelData {
	plan_status := get_plan_status(mut db, user_id)!
	bucket := 'key:user:${user_id}'
	usage := get_usage_month(mut db, bucket) or {
		UsageSummary{
			bucket: bucket
			used:   0
			lim:    0
			remaining: 0
			plan:  plan_status.plan
		}
	}
	return PanelData{
		plan_status: plan_status
		usage_month: usage
	}
}