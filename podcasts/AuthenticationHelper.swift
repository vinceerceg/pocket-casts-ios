import Foundation
import PocketCastsDataModel
import PocketCastsServer
import PocketCastsUtils
import AuthenticationServices

class AuthenticationHelper {
    static func validateLogin(_ appleIDCredential: ASAuthorizationAppleIDCredential) async throws {
        let response = try await ApiServerHandler.shared.validateLogin(identityToken: appleIDCredential.identityToken)
        handleSuccessfulSignIn(response)
        if let identityToken = appleIDCredential.identityToken {
            ServerSettings.appleAuthIdentityToken = String(data: identityToken, encoding: .utf8)
            ServerSettings.appleAuthUserID = appleIDCredential.user
        }
    }

    static func validateAppleSSOCredentials() {
        guard ServerSettings.appleAuthUserID != nil else {
            // No need to Check if we don't have a user ID
            return
        }
        Task {
            let state = try await ApiServerHandler.shared.ssoCredentialState()
            switch state {
            case .revoked, .transferred:
                FileLog.shared.addMessage("Apple SSO token has been revoked. Signing user out.")
                SyncManager.signout()
            default:
                break
            }
        }
    }

    static func observeAppleSSOEvents() {
        guard ServerSettings.appleAuthUserID != nil else {
            // No need to observe if we don't have a user ID
            return
        }
        NotificationCenter.default.addObserver(forName: ASAuthorizationAppleIDProvider.credentialRevokedNotification, object: nil, queue: .main) { _ in
            FileLog.shared.addMessage("Apple SSO token has been revoked. Signing user out.")
            SyncManager.signout()
        }
    }

    private static func handleSuccessfulSignIn(_ response: AuthenticationResponse) {
        SyncManager.clearTokensFromKeyChain()

        ServerSettings.userId = response.uuid
        ServerSettings.syncingV2Token = response.token

        // we've signed in, set all our existing podcasts to be non synced
        DataManager.sharedManager.markAllPodcastsUnsynced()

        ServerSettings.clearLastSyncTime()
        ServerSettings.setSyncingEmail(email: response.email)

        NotificationCenter.default.post(name: .userLoginDidChange, object: nil)
        // TODO: Track login source details
        //        Analytics.track(.userSignedIn)

        RefreshManager.shared.refreshPodcasts(forceEvenIfRefreshedRecently: true)
        Settings.setPromotionFinishedAcknowledged(true)
        Settings.setLoginDetailsUpdated()
    }
}
