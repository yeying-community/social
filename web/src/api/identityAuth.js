import http from './httpRequest'

export const createIdentityLoginSession = () => http({
	url: '/identity/login/session',
	method: 'post'
})

export const getIdentityLoginStatus = (sessionId) => http({
	url: '/identity/login/status',
	method: 'get',
	params: { sessionId }
})

export const createWalletIdentityLoginSession = () => http({
	url: '/identity/login/session',
	method: 'post'
})

export const verifyWalletIdentityLogin = (data) => http({
	url: '/identity/login/verify',
	method: 'post',
	data
})
