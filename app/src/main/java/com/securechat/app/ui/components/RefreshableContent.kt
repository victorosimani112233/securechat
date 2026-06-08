package com.securechat.app.ui.components

import androidx.compose.foundation.layout.Box
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.pulltorefresh.PullToRefreshContainer
import androidx.compose.material3.pulltorefresh.rememberPullToRefreshState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.nestedscroll.nestedScroll

/**
 * Material 3 PullToRefresh wrapper'i — uzun liste ekranlarinda kullanilir.
 *
 * Kullanim:
 * ```
 * RefreshableContent(
 *     isRefreshing = viewModel.isRefreshing,
 *     onRefresh = { viewModel.refresh() }
 * ) {
 *     LazyColumn(...) { ... }
 * }
 * ```
 *
 * Davranis:
 *   - Kullanici listenin tepesinden asagi cektiginde onRefresh tetiklenir.
 *   - isRefreshing true iken spinner gosterilir, refresh durana kadar
 *     PullToRefreshContainer indicator'i kalir.
 *   - isRefreshing false yapildiginda spinner kaybolur ve state reset olur.
 *
 * NOT: WS reconnect + Flow tabanli list'lerde gercek "refresh"e gerek olmayabilir
 * (her data degisikligi zaten reactive geliyordur), ama kullaniciya feedback
 * + manuel "yenile" intention'i icin yardimcidir.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RefreshableContent(
    isRefreshing: Boolean,
    onRefresh: () -> Unit,
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit
) {
    val pullState = rememberPullToRefreshState()

    // Kullanici tetikledi -> dis dunyaya bildir
    if (pullState.isRefreshing) {
        LaunchedEffect(Unit) { onRefresh() }
    }

    // Dis dunyada is bitti -> indicator'i durdur
    LaunchedEffect(isRefreshing) {
        if (!isRefreshing && pullState.isRefreshing) {
            pullState.endRefresh()
        }
    }

    Box(modifier = modifier.nestedScroll(pullState.nestedScrollConnection)) {
        content()
        PullToRefreshContainer(
            state = pullState,
            modifier = Modifier.align(Alignment.TopCenter)
        )
    }
}
