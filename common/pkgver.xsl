<?xml version="1.0" encoding="ISO-8859-1"?>

<xsl:stylesheet
      xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
      version="1.0">

<xsl:output method="text"/>
<!-- Parameters -->

  <xsl:param name="package"/>

<!-- End parameters -->

<!-- Start of templates -->
  <xsl:template match="/">
    <xsl:apply-templates select="//chapter[
                                @id='chapter-building-system' or
    @id='chapter-bootable']/sect1/sect1info[address=$package]"/>
  </xsl:template>

  <xsl:template match="sect1info">
    <xsl:if test="../@id != 'ch-bootable-grub'">
      <xsl:value-of select="productnumber"/>
    </xsl:if>
  </xsl:template>

</xsl:stylesheet>
