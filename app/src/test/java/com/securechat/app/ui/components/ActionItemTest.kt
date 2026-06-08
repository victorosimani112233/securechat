package com.securechat.app.ui.components

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import com.google.common.truth.Truth.assertThat
import org.junit.Test

/**
 * ActionItem data class davranis kontratlari.
 *
 * Bu pure data class ve ActionItem'lar SecureChatActionSheet'in sundugu menu
 * item'lari icin compose-tabanli olmadan dogrulamak — kullanim sirasinda
 * baska modullerin bunlari liste olarak kurmasini guvence altina alir.
 */
class ActionItemTest {

    @Test
    fun `default ActionItem danger false ve onClick atanir`() {
        var clicked = false
        val item = ActionItem(
            label = "Test",
            icon = Icons.Default.Edit,
            onClick = { clicked = true }
        )

        assertThat(item.label).isEqualTo("Test")
        assertThat(item.danger).isFalse()
        item.onClick()
        assertThat(clicked).isTrue()
    }

    @Test
    fun `danger=true tehlikeli aksiyon isaretler`() {
        val item = ActionItem(
            label = "Sil",
            icon = Icons.Default.Delete,
            danger = true,
            onClick = {}
        )

        assertThat(item.danger).isTrue()
    }

    @Test
    fun `liste sirasi korunur`() {
        val items = listOf(
            ActionItem("Yanitla", Icons.Default.Edit) {},
            ActionItem("Sil", Icons.Default.Delete, danger = true) {}
        )

        assertThat(items.map { it.label }).containsExactly("Yanitla", "Sil").inOrder()
        assertThat(items.last().danger).isTrue()
    }
}
