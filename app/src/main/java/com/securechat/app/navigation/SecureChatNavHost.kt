package com.securechat.app.navigation

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.EnterTransition
import androidx.compose.animation.ExitTransition
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Chat
import androidx.compose.material.icons.filled.Call
import androidx.compose.material.icons.filled.Contacts
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.securechat.app.ui.screen.CallHistoryScreen
import com.securechat.app.ui.screen.CallScreen
import com.securechat.app.ui.screen.ChatInfoScreen
import com.securechat.app.ui.screen.ChatScreen
import com.securechat.app.ui.screen.ContactsScreen
import com.securechat.app.ui.screen.ConversationsScreen
import com.securechat.app.ui.screen.BulkMessageScreen
import com.securechat.app.ui.screen.AddGroupMemberScreen
import com.securechat.app.ui.screen.CreateGroupScreen
import com.securechat.app.ui.screen.GroupInfoScreen
import com.securechat.app.ui.screen.EmailOtpScreen
import com.securechat.app.ui.screen.OtpVerificationScreen
import com.securechat.app.ui.screen.PhoneVerificationScreen
import com.securechat.app.ui.screen.ScheduledMessagesScreen
import com.securechat.app.ui.screen.SettingsScreen
import com.securechat.app.ui.screen.SplashScreen
import com.securechat.app.backup.BackupScreen
import com.securechat.app.ui.theme.LocalDarkTheme
import com.securechat.network.model.CallType

private const val ANIM_DURATION = 300

// Ileri navigasyon: yeni ekran sagdan tam kayarak gelir, eski ekran sola kayar
private fun defaultEnter(): EnterTransition =
    slideInHorizontally(tween(ANIM_DURATION)) { it }

private fun defaultExit(): ExitTransition =
    slideOutHorizontally(tween(ANIM_DURATION)) { -it / 3 }

// Geri navigasyon: mevcut ekran saga kayarak cikar, onceki ekran soldan gelir
private fun defaultPopEnter(): EnterTransition =
    slideInHorizontally(tween(ANIM_DURATION)) { -it / 3 }

private fun defaultPopExit(): ExitTransition =
    slideOutHorizontally(tween(ANIM_DURATION)) { it }

/** Alt navigasyon bar sekmeleri. */
private enum class BottomTab(val route: String, val label: String, val icon: ImageVector) {
    SOHBET("conversations", "Sohbet", Icons.AutoMirrored.Filled.Chat),
    ARAMA("call_history", "Arama", Icons.Default.Call),
    REHBER("contacts", "Rehber", Icons.Default.Contacts),
    AYARLAR("settings", "Ayarlar", Icons.Default.Settings),
}

/** Alt bar'ın gösterileceği route'lar. */
private val BOTTOM_BAR_ROUTES = BottomTab.entries.map { it.route }.toSet()

@Composable
fun SecureChatNavHost(
    navController: NavHostController = rememberNavController(),
    startDestination: String = "conversations",
    skipSplash: Boolean = false,
    onUserRegistered: (name: String, phone: String, registrationToken: String?) -> Unit = { _, _, _ -> },
    apiBaseUrl: String = ""
) {
    val actualStartDestination = if (skipSplash) startDestination else "splash"
    val navBackStackEntry by navController.currentBackStackEntryAsState()
    val currentRoute = navBackStackEntry?.destination?.route
    val showBottomBar = currentRoute in BOTTOM_BAR_ROUTES
    val dark = LocalDarkTheme.current

    // NavHost tam ekran, bottom bar overlay olarak ustune biner.
    // Boylece bottom bar gizlendiginde NavHost boyutu degismez, animasyon bozulmaz.
    Box(Modifier.fillMaxSize().systemBarsPadding()) {
        NavHost(
            navController = navController,
            startDestination = actualStartDestination,
            modifier = Modifier.fillMaxSize(),
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
                        // Telefon + isim girildi — sonraki ekran e-posta OTP
                        // (Server SMTP yapilandirilmamissa "Atla" ile direk register)
                        navController.navigate("auth/email_otp/${java.net.URLEncoder.encode(name, "UTF-8")}/${java.net.URLEncoder.encode(phone, "UTF-8")}") {
                            popUpTo("auth/phone") { inclusive = true }
                        }
                    }
                )
            }

            composable("auth/email_otp/{name}/{phone}") { backStackEntry ->
                val name = java.net.URLDecoder.decode(backStackEntry.arguments?.getString("name") ?: "", "UTF-8")
                val phone = java.net.URLDecoder.decode(backStackEntry.arguments?.getString("phone") ?: "", "UTF-8")
                EmailOtpScreen(
                    onVerified = { regToken ->
                        // OTP dogrulandi — registrationToken ile register cagir
                        onUserRegistered(name, phone, regToken)
                        navController.navigate("conversations") {
                            popUpTo("auth/phone") { inclusive = true }
                        }
                    },
                    onSkip = {
                        // SMTP devre disi — registrationToken'siz register
                        onUserRegistered(name, phone, null)
                        navController.navigate("conversations") {
                            popUpTo("auth/phone") { inclusive = true }
                        }
                    },
                    onBackClick = { navController.popBackStack() },
                    apiBaseUrl = apiBaseUrl
                )
            }

            composable("auth/otp/{phoneNumber}") { backStackEntry ->
                val phoneNumber = backStackEntry.arguments?.getString("phoneNumber") ?: ""
                OtpVerificationScreen(
                    phoneNumber = phoneNumber,
                    onVerified = {
                        navController.navigate("conversations") {
                            popUpTo("auth/phone") { inclusive = true }
                        }
                    },
                    onBackupRestore = {
                        // Once conversations'a git, sonra backup ekranina yonlendir
                        navController.navigate("conversations") {
                            popUpTo("auth/phone") { inclusive = true }
                        }
                        navController.navigate("backup")
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
                    onNewChat = {
                        navController.navigate("contacts") {
                            popUpTo("conversations") { saveState = true }
                            launchSingleTop = true
                            restoreState = true
                        }
                    },
                    onNewGroup = { navController.navigate("create_group") },
                    onBulkMessage = { navController.navigate("bulk_message") },
                    onScheduledMessages = { navController.navigate("scheduled_messages") },
                    onSettingsClick = {
                        navController.navigate("settings") {
                            popUpTo("conversations") { saveState = true }
                            launchSingleTop = true
                            restoreState = true
                        }
                    },
                    onCallHistoryClick = {
                        navController.navigate("call_history") {
                            popUpTo("conversations") { saveState = true }
                            launchSingleTop = true
                            restoreState = true
                        }
                    },
                    onContactsClick = {
                        navController.navigate("contacts") {
                            popUpTo("conversations") { saveState = true }
                            launchSingleTop = true
                            restoreState = true
                        }
                    }
                )
            }

            composable(
                "create_group",
                enterTransition = { slideInVertically(tween(ANIM_DURATION)) { it } },
                exitTransition = { slideOutVertically(tween(ANIM_DURATION)) { -it / 3 } },
                popEnterTransition = { slideInVertically(tween(ANIM_DURATION)) { -it / 3 } },
                popExitTransition = { slideOutVertically(tween(ANIM_DURATION)) { it } }
            ) {
                CreateGroupScreen(
                    onGroupCreated = { groupId ->
                        navController.navigate("chat/$groupId") {
                            popUpTo("conversations")
                        }
                    },
                    onBackClick = { navController.popBackStack() }
                )
            }

            composable(
                "bulk_message",
                enterTransition = { slideInVertically(tween(ANIM_DURATION)) { it } },
                exitTransition = { slideOutVertically(tween(ANIM_DURATION)) { -it / 3 } },
                popEnterTransition = { slideInVertically(tween(ANIM_DURATION)) { -it / 3 } },
                popExitTransition = { slideOutVertically(tween(ANIM_DURATION)) { it } }
            ) {
                BulkMessageScreen(onBackClick = { navController.popBackStack() })
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
                        navController.navigate("add_member/$groupId")
                    },
                    onMemberClick = { memberId ->
                        navController.navigate("chat_info/$memberId")
                    }
                )
            }

            composable("add_member/{groupId}") {
                AddGroupMemberScreen(
                    onMembersAdded = { navController.popBackStack() },
                    onBackClick = { navController.popBackStack() }
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
                    onBackClick = { navController.popBackStack() },
                    onScheduledMessages = {
                        navController.navigate("scheduled_messages/1")
                    },
                    onBackupClick = {
                        navController.navigate("backup")
                    },
                    onAccountDeleted = {
                        navController.navigate("auth/phone") {
                            popUpTo(0) { inclusive = true }
                        }
                    }
                )
            }

            composable("backup") {
                BackupScreen(
                    onBackClick = { navController.popBackStack() }
                )
            }

            composable("scheduled_messages") {
                ScheduledMessagesScreen(
                    onBackClick = { navController.popBackStack() }
                )
            }

            composable("scheduled_messages/{initialTab}") { backStackEntry ->
                val tab = backStackEntry.arguments?.getString("initialTab")?.toIntOrNull() ?: 0
                ScheduledMessagesScreen(
                    onBackClick = { navController.popBackStack() },
                    initialTab = tab
                )
            }
        }

        // Bottom bar — NavHost ustune overlay olarak biner
        AnimatedVisibility(
            visible = showBottomBar,
            modifier = Modifier.align(Alignment.BottomCenter),
            enter = slideInVertically(tween(200)) { it },
            exit = slideOutVertically(tween(200)) { it }
        ) {
            NavigationBar(
                containerColor = if (dark) Color(0xFF0D1014).copy(alpha = 0.95f)
                                 else Color.White.copy(alpha = 0.95f),
                tonalElevation = 0.dp
            ) {
                BottomTab.entries.forEach { tab ->
                    NavigationBarItem(
                        selected = currentRoute == tab.route,
                        onClick = {
                            if (currentRoute != tab.route) {
                                navController.navigate(tab.route) {
                                    popUpTo("conversations") { saveState = true }
                                    launchSingleTop = true
                                    restoreState = true
                                }
                            }
                        },
                        icon = {
                            Icon(
                                tab.icon,
                                contentDescription = tab.label,
                                modifier = Modifier.padding(vertical = 2.dp)
                            )
                        },
                        colors = NavigationBarItemDefaults.colors(
                            selectedIconColor = MaterialTheme.colorScheme.primary,
                            selectedTextColor = MaterialTheme.colorScheme.primary,
                            indicatorColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.12f),
                            unselectedIconColor = MaterialTheme.colorScheme.onSurfaceVariant,
                            unselectedTextColor = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    )
                }
            }
        }
    }
}
