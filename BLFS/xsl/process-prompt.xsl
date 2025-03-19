<?xml version="1.0" encoding="ISO-8859-1"?>
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
    version="1.0">

  <xsl:template name="process-prompt">
    <xsl:param name="instructions"/>
    <xsl:param name="root-seen"/>
    <xsl:param name="prompt-seen"/>

<!-- Isolate the current instruction -->
    <xsl:variable name="current-instr" select="$instructions[1]"/>

    <xsl:choose>
<!--============================================================-->
<!-- First, if we have an empty tree, close everything and exit -->
      <xsl:when test="not($current-instr)">
        <xsl:if test="$prompt-seen">
          <xsl:call-template name="end-prompt"/>
        </xsl:if>
        <xsl:if test="$root-seen">
          <xsl:call-template name="end-root"/>
        </xsl:if>
      </xsl:when><!-- end empty tree -->
<!--============================================================-->
      <xsl:when test="$current-instr[@role='root']">
        <xsl:choose>
          <xsl:when test="$current-instr//prompt">
            <xsl:if test="not($root-seen)">
              <xsl:call-template name="begin-root"/>
            </xsl:if>
            <xsl:text>&#xA;</xsl:text>
            <xsl:if test="not($prompt-seen)">
              <xsl:copy-of
                select="substring-before($current-instr//text()[1],'&#xA;')"/>
              <xsl:text> &lt;&lt; PROMPT_EOF
</xsl:text>
            </xsl:if>
            <xsl:apply-templates
              select="$current-instr/userinput/node()[position()>1]"/>
            <xsl:call-template name="process-prompt">
              <xsl:with-param
                 name="instructions"
                 select="$instructions[position()>1]"/>
              <xsl:with-param name="root-seen" select="boolean(1)"/>
              <xsl:with-param name="prompt-seen" select="boolean(1)"/>
            </xsl:call-template>
          </xsl:when><!-- end prompt as root -->
<!--____________________________________________________________ -->
          <xsl:otherwise><!-- we have no prompt -->
            <xsl:if test="$prompt-seen">
              <xsl:text>
quit
PROMPT_EOF</xsl:text>
            </xsl:if>
            <xsl:apply-templates
              select="$current-instr"
              mode="config"/>
            <!-- the above will call "end-root" if the next screen
                 sibling is not role="root". We need to pass root-seen=false
                 in this case. Otherwise, we need to pass root-seen=true.
                 So create a variable -->
            <xsl:variable name="rs"
              select="$instructions[2][@role='root']"/>
            <xsl:call-template name="process-prompt">
              <xsl:with-param
                 name="instructions"
                 select="$instructions[position()>1]"/>
              <xsl:with-param name="root-seen" select="boolean($rs)"/>
              <xsl:with-param name="prompt-seen" select="boolean(0)"/>
            </xsl:call-template>
          </xsl:otherwise><!-- end no prompt -->
<!--____________________________________________________________ -->
        </xsl:choose>
      </xsl:when><!-- role="root" -->
<!--============================================================-->
      <xsl:otherwise><!-- no role -->
        <xsl:if test="$prompt-seen">
          <xsl:text>
quit
PROMPT_EOF</xsl:text>
        </xsl:if>
        <xsl:if test="$root-seen">
          <xsl:call-template name="end-root"/>
        </xsl:if>
        <xsl:apply-templates select="$current-instr"/>
        <xsl:call-template name="process-prompt">
          <xsl:with-param
             name="instructions"
             select="$instructions[position()>1]"/>
          <xsl:with-param name="root-seen" select="boolean(0)"/>
          <xsl:with-param name="prompt-seen" select="boolean(0)"/>
        </xsl:call-template>
      </xsl:otherwise><!-- no role -->
<!--============================================================-->
    </xsl:choose>
  </xsl:template>

  <xsl:template match="prompt"/>
</xsl:stylesheet>
