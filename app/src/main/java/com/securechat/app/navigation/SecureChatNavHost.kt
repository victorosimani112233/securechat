package com.securechat.app.navigation

import androidx.compose.animation.EnterTransition
import androidx.compose.animation.ExitTransition
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.runtime.Composable
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import com.securechat.app.ui.screen.CallHistoryScreen
import com.securechat.app.ui.screen.CallScreen
import com.securechat.app.ui.screen.ChatInfoScreen
import com.securechat.app.ui.screen.ChatScreen
import com.securechat.app.ui.screen.ContactsScreen
import com.securechat.app.ui.screen.ConversationsScreen
import com.securechat.app.ui.screen.CreateGroupScreen
import com.securechat.app.ui.screen.GroupInfoScreen
import com.securechat.app.ui.screen.OtpVerificationScreen
import com.securechat.app.ui.screen.PhoneVerificationScreen
import com.securechat.app.ui.screen.SettingsScreen
import com.securechat.app.ui.screen.SplashScreen
import com.securechat.network.model.CallType
import com.securechat.storage.domain.Conversation

private const val ANIM_DURATION = 250

private fun defaultEnter(): EnterTransition =
    fadeIn(tween(ANIM_DURATION)) + slideInHorizontally(tween(ANIM_DURATION)) { it / 6 }

private fun defaultExit(): ExitTransition =
    fadeOut(tween(ANIM_DURATION)) + slideOutHorizontally(tween(ANIM_DURATION)) { -it / 6 }

private fun defaultPopEnter(): EnterTransition =
    fadeIn(tween(ANIM_DURATION)) + slideInHorizontally(tween(ANIM_DURATION)) { -it / 6 }

private fun defaultPopExit(): ExitTransition =
    fadeOut(tween(ANIM_DURATION)) + slideOutHorizontally(tween(ANIM_DURATION)) { it / 6 }

@Composable
fun SecureChatNavHost(
    navController: NavHostController = rememberNavController(),
    startDestination: String = "conversations",
    onUserRegistered: (name: String, phone: String) -> Unit = { _, _ -> }
) {
    // Splash her zaman ilk gosterilir, sonra gercek hedef ekrana gider
    val actualStartDestination = "splash"

    NavHost(
        navController = navController,
        startDestination = actualStartDestination,
        enterTransition = { defaultEnter() },
        exitTransition = { defaultExit() },
        popEnterTransition = { defaultPopEnter() },
        popExitTransition = { defaultPopExit() }
    ) {
        composable(
            "splash",
            enterTransition = { fadeIn(tween(0)) },
            exitTransition = { fadeOut(tween(300)) }
        ) {
            SplashScreen(
                onSplashFinished = {
                    navController.navigate(startDestination) {
                        popUpTo("splash") { inclusive = true }
                    }
                }
            )
        }

        composable("auth/phone") {
            PhoneVerificationScreen(
                onVerified = { name, phone ->
                    // OTP bypass - doğrudan kayıt et ve ana ekrana git
                    onUserRegistered(name, phone)
                    navController.navigate("conversations") {
                        popUpTo("auth/phone") { inclusive = true }
                    }
                }
            )
        }

        composable("auth/otp/{phoneNumber}") { backStackEntry ->
            val phoneNumber = backStackEntry.arguments?.getString("phoneNumber") ?: ""
            OtpVerificationScreen(
                phoneNumber = phoneNumber,
                onVerified = {
                    // Başarılı doğrulama sonrası ana ekrana git
                    navController.navigate("conversations") {
                        popUpTo("auth/phone") { inclusive = true }
                    }
                },
                onBackClick = { navController.popBackStack() }
            )
        }

        composable("conversations") {
            ConversationsScreen(
                onConversationClick = { conversationId ->
                    navController.navigate("chat/$conversationId")
                },
                onConversationInfoClick = { conversation ->
                    if (conversation.isGroup) {
                        navController.navigate("group_info/${conversation.id}")
                    } else {
                        navController.navigate("chat_info/${conversation.id}")
                    }
                },
                onNewChat = { navController.navigate("contacts") },
                onNewGroup = { navController.navigate("create_group") },
                onSettingsClick = { navController.navigate("settings") },
                onCallHistoryClick = { navController.navigate("call_history") }
            )
        }

        composable("create_group") {
            CreateGroupScreen(
                onGroupCreated = { groupId ->
                    navController.navigate("chat/$groupId") {
                        popUpTo("conversations")
                    }
                },
                onBackClick = { navController.popBackStack() }
            )
        }

        composable("chat/{conversationId}") {
            val conversationId = it.arguments?.getString("conversationId") ?: ""
            ChatScreen(
                conversationId = conversationId,
                onBackClick = { navController.popBackStack() },
                onVoiceCallClick = { peerId ->
                    navController.navigate("call/$peerId/VOICE")
                },
                onVideoCallClick = { peerId ->
                    navController.navigate("call/$peerId/VIDEO")
                },
                onChatInfoClick = { convId ->
                    navController.navigate("chat_info/$convId")
                },
                onGroupInfoClick = { groupId ->
                    navController.navigate("group_info/$groupId")
                }
            )
        }

        composable("group_info/{groupId}") { backStackEntry ->
            val groupId = backStackEntry.arguments?.getString("groupId") ?: ""
            GroupInfoScreen(
                groupId = groupId,
                onBackClick = { navController.popBackStack() },
                onAddMember = {
                    // TODO: Navigate to contact selection for adding members
                }
            )
        }

        composable("chat_info/{conversationId}") { backStackEntry ->
            val conversationId = backStackEntry.arguments?.getString("conversationId") ?: ""
            val context = androidx.compose.ui.platform.LocalContext.current
            ChatInfoScreen(
                conversationId = conversationId,
                onBackClick = { navController.popBackStack() },
                onMessageClick = { messageId ->
                    navController.popBackStack()
                },
                onMediaClick = { message ->
                    // content formatı: "dosyaAdi|mimeType|dosyaBoyutu|yerelDosyaYolu"
                    val parts = message.content.split("|")
                    val mimeType = parts.getOrNull(1) ?: "application/octet-stream"
                    val filePath = parts.getOrNull(3)
                    if (!filePath.isNullOrBlank()) {
                        com.securechat.app.util.FileOpenHelper.openFile(
                            context = context,
                            filePath = filePath,
                            mimeType = mimeType
                        )
                    }
                }
            )
        }

        composable("contacts") {
            ContactsScreen(
                onContactClick = { userId ->
                    navController.navigate("chat/$userId") {
                        popUpTo("conversations")
                    }
                },
                onBackClick = { navController.popBackStack() }
            )
        }

        composable("call/{peerId}/{callType}") { backStackEntry ->
            val peerId = backStackEntry.arguments?.getString("peerId") ?: ""
            val callTypeStr = backStackEntry.arguments?.getString("callType") ?: "VOICE"
            val callType = try {
                CallType.valueOf(callTypeStr)
            } catch (_: IllegalArgumentException) {
                CallType.VOICE
            }
            CallScreen(
                peerId = peerId,
                callType = callType,
                onCallEnded = { navController.popBackStack() }
            )
        }

        composable("call_history") {
            CallHistoryScreen(
                onBackClick = { navController.popBackStack() },
                onCallClick = { peerId, callType ->
                    navController.navigate("call/$peerId/$callType")
                }
            )
        }

        composable("settings") {
            SettingsScreen(
                onBackClick = { navController.popBackStack() }
            )
        }
    }
}
