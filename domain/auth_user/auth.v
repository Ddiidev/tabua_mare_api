module auth_user

// UserData representa os dados publicos do usuario retornados por /auth/me.
pub struct UserData {
pub:
	id         int
	email      string
	name       string
	avatar_url string
	plan       string
	provider   string
}
