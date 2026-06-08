package com.securechat.app.data.incoming

import com.google.common.truth.Truth.assertThat
import com.securechat.crypto.model.EnvelopeType
import org.junit.Test

/**
 * EnvelopeFormatDetector birim testleri. Tum format tipleri icin pozitif ve
 * negatif yollar dogrulanir.
 */
class EnvelopeFormatDetectorTest {

    @Test
    fun `E2EE prefix - DirectE2EE format tespit edilir`() {
        val env = "E2EE:v1:PREKEY:42:dGVzdA=="

        val result = EnvelopeFormatDetector.detect(env)

        assertThat(result).isInstanceOf(EnvelopeFormat.DirectE2EE::class.java)
        val direct = result as EnvelopeFormat.DirectE2EE
        assertThat(direct.type).isEqualTo(EnvelopeType.PREKEY)
        assertThat(direct.regId).isEqualTo(42)
        assertThat(direct.ciphertextB64).isEqualTo("dGVzdA==")
    }

    @Test
    fun `E2EE SIGNAL type tanir`() {
        val env = "E2EE:v1:SIGNAL:7:YWFh"

        val result = EnvelopeFormatDetector.detect(env)

        assertThat((result as EnvelopeFormat.DirectE2EE).type).isEqualTo(EnvelopeType.SIGNAL)
    }

    @Test
    fun `GROUPSK v1 - GroupV1 format tespit edilir`() {
        val env = "GROUPSK:v1:group_abc:Test Grup:Y2lwaGVy"

        val result = EnvelopeFormatDetector.detect(env)

        assertThat(result).isInstanceOf(EnvelopeFormat.GroupV1::class.java)
        val g = result as EnvelopeFormat.GroupV1
        assertThat(g.groupId).isEqualTo("group_abc")
        assertThat(g.groupName).isEqualTo("Test Grup")
        assertThat(g.ciphertextB64).isEqualTo("Y2lwaGVy")
    }

    @Test
    fun `SKDM prefix - Skdm format tespit edilir`() {
        val env = "SKDM:group_xyz:c2tkbQ=="

        val result = EnvelopeFormatDetector.detect(env)

        assertThat(result).isInstanceOf(EnvelopeFormat.Skdm::class.java)
        val s = result as EnvelopeFormat.Skdm
        assertThat(s.groupId).isEqualTo("group_xyz")
        assertThat(s.skdmB64).isEqualTo("c2tkbQ==")
    }

    @Test
    fun `GROUP prefix 4-parca - GroupLegacy with groupName`() {
        val env = "GROUP:gid1:Grup Adi:MSGID:m1:icerik"

        val result = EnvelopeFormatDetector.detect(env)

        assertThat(result).isInstanceOf(EnvelopeFormat.GroupLegacy::class.java)
        val g = result as EnvelopeFormat.GroupLegacy
        assertThat(g.groupId).isEqualTo("gid1")
        assertThat(g.groupName).isEqualTo("Grup Adi")
        assertThat(g.payload).isEqualTo("MSGID:m1:icerik")
    }

    @Test
    fun `GROUP prefix 3-parca - GroupLegacy without groupName`() {
        val env = "GROUP:gid1:icerik"

        val result = EnvelopeFormatDetector.detect(env)

        val g = result as EnvelopeFormat.GroupLegacy
        assertThat(g.groupId).isEqualTo("gid1")
        assertThat(g.groupName).isNull()
        assertThat(g.payload).isEqualTo("icerik")
    }

    @Test
    fun `prefix yok - DirectLegacy as is`() {
        val env = "MSGID:abc:duz metin"

        val result = EnvelopeFormatDetector.detect(env)

        assertThat(result).isInstanceOf(EnvelopeFormat.DirectLegacy::class.java)
        assertThat((result as EnvelopeFormat.DirectLegacy).payload).isEqualTo(env)
    }

    @Test
    fun `E2EE bozuk regId - Unknown`() {
        val env = "E2EE:v1:PREKEY:not_a_number:b64"

        val result = EnvelopeFormatDetector.detect(env)

        assertThat(result).isEqualTo(EnvelopeFormat.Unknown)
    }

    @Test
    fun `E2EE bozuk type - Unknown`() {
        val env = "E2EE:v1:UNKNOWN_TYPE:1:b64"

        val result = EnvelopeFormatDetector.detect(env)

        assertThat(result).isEqualTo(EnvelopeFormat.Unknown)
    }

    @Test
    fun `E2EE eksik parca - Unknown`() {
        val env = "E2EE:v1:PREKEY:42"

        val result = EnvelopeFormatDetector.detect(env)

        assertThat(result).isEqualTo(EnvelopeFormat.Unknown)
    }

    @Test
    fun `GROUPSK eksik parca - Unknown`() {
        val env = "GROUPSK:v1:gid"

        val result = EnvelopeFormatDetector.detect(env)

        assertThat(result).isEqualTo(EnvelopeFormat.Unknown)
    }

    @Test
    fun `SKDM eksik parca - Unknown`() {
        val env = "SKDM:onlygroup"

        val result = EnvelopeFormatDetector.detect(env)

        assertThat(result).isEqualTo(EnvelopeFormat.Unknown)
    }
}
