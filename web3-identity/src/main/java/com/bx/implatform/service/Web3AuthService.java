package com.bx.implatform.service;

import com.bx.implatform.dto.SiweNonceDTO;
import com.bx.implatform.dto.SiweVerifyDTO;
import com.bx.implatform.dto.WalletLinkDTO;
import com.bx.implatform.dto.WalletUnlinkDTO;
import com.bx.implatform.session.UserSession;
import com.bx.implatform.vo.LoginVO;
import com.bx.implatform.vo.SiweNonceVO;
import com.bx.implatform.vo.Web3VerifyVO;

public interface Web3AuthService {

    SiweNonceVO issueNonce(SiweNonceDTO dto);

    LoginVO verifyAndLogin(SiweVerifyDTO dto);

    LoginVO refreshToken(String refreshToken);

    void linkWallet(UserSession session, WalletLinkDTO dto);

    void unlinkWallet(UserSession session, WalletUnlinkDTO dto);
}
