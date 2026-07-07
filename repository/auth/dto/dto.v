module dto

// User representa um usuario do dominio de negocio (auth/dash).
pub struct User {
pub mut:
	id                    int
	email                 string
	name                  string
	avatar_url            string
	plan                  string
	stripe_customer_id    string
	stripe_subscription_id string
}

// ApiKey representa uma chave de API paga.
pub struct ApiKey {
pub mut:
	id         int
	user_id    int
	key_value  string
	label      string
	plan       string
	revoked   bool
}
