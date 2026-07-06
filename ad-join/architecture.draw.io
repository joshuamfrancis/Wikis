<mxfile host="app.diagrams.net" agent="architecture-export" version="24.0.0">
  <diagram id="ad-direct-join" name="Direct On-Prem AD Join">
    <mxGraphModel dx="1100" dy="800" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="1169" pageHeight="826" math="0" shadow="0">
      <root>
        <mxCell id="0"/>
        <mxCell id="1" parent="0"/>

        <!-- Title -->
        <mxCell id="title" value="Direct On-Prem AD Join — Windows EC2 (no Directory Service)" style="text;html=1;fontSize=18;fontStyle=1;align=center;verticalAlign=middle;fillColor=none;strokeColor=none;fontColor=#1B2A3A;" vertex="1" parent="1">
          <mxGeometry x="40" y="16" width="1090" height="30" as="geometry"/>
        </mxCell>
        <mxCell id="subtitle" value="Central R53 outbound endpoint + forwarding rule shared via RAM · self-managed join lifecycle" style="text;html=1;fontSize=12;align=center;verticalAlign=middle;fillColor=none;strokeColor=none;fontColor=#5A6B7B;" vertex="1" parent="1">
          <mxGeometry x="40" y="46" width="1090" height="20" as="geometry"/>
        </mxCell>

        <!-- ON-PREM container -->
        <mxCell id="onprem" value="On-Premises" style="rounded=1;whiteSpace=wrap;html=1;verticalAlign=top;fontStyle=1;fontSize=13;fillColor=#EEF3EE;strokeColor=#5A7D5A;fontColor=#33502F;arcSize=6;" vertex="1" parent="1">
          <mxGeometry x="40" y="90" width="230" height="180" as="geometry"/>
        </mxCell>
        <mxCell id="dcs" value="Active Directory DCs&#10;corp.example.com" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#FFFFFF;strokeColor=#5A7D5A;fontColor=#33502F;fontSize=11;" vertex="1" parent="1">
          <mxGeometry x="70" y="130" width="170" height="55" as="geometry"/>
        </mxCell>
        <mxCell id="dcinfo" value="DC IPs 10.10.0.10 / .11&#10;Target OU for computer objects (delegated)" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#FFFFFF;strokeColor=#5A7D5A;fontColor=#5A6B7B;fontSize=10;" vertex="1" parent="1">
          <mxGeometry x="70" y="197" width="170" height="60" as="geometry"/>
        </mxCell>

        <!-- DX / VPN + TGW -->
        <mxCell id="dxtgw" value="Direct Connect / VPN&#10;+ Transit Gateway&#10;(hybrid link)" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#E8EEF5;strokeColor=#2F5D8A;fontColor=#1B2A3A;fontSize=11;fontStyle=1;" vertex="1" parent="1">
          <mxGeometry x="310" y="120" width="115" height="120" as="geometry"/>
        </mxCell>

        <!-- NETWORK ACCOUNT container -->
        <mxCell id="netacct" value="Central Network Account — DNS hub VPC" style="rounded=1;whiteSpace=wrap;html=1;verticalAlign=top;fontStyle=1;fontSize=13;fillColor=#E8EEF5;strokeColor=#2F5D8A;fontColor=#1B2A3A;arcSize=6;" vertex="1" parent="1">
          <mxGeometry x="465" y="90" width="290" height="230" as="geometry"/>
        </mxCell>
        <mxCell id="outep" value="R53 Resolver — OUTBOUND endpoint&#10;ENIs in 2 subnets / 2 AZs&#10;SG: egress UDP/TCP 53" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#FFFFFF;strokeColor=#2F5D8A;fontColor=#1B2A3A;fontSize=11;fontStyle=1;" vertex="1" parent="1">
          <mxGeometry x="490" y="145" width="240" height="68" as="geometry"/>
        </mxCell>
        <mxCell id="fwdrule" value="Forwarding Rule (FORWARD)&#10;corp.example.com → DC IPs:53&#10;shared via AWS RAM · no inbound endpoint needed" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#FFF7EE;strokeColor=#B5651D;fontColor=#7A4512;fontSize=11;fontStyle=1;" vertex="1" parent="1">
          <mxGeometry x="490" y="223" width="240" height="80" as="geometry"/>
        </mxCell>

        <!-- RAM share -->
        <mxCell id="ram" value="AWS RAM Resource Share&#10;type: ResolverRule&#10;target: Workloads OU (auto-accept in org)" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#FFF7EE;strokeColor=#B5651D;fontColor=#7A4512;fontSize=11;fontStyle=1;" vertex="1" parent="1">
          <mxGeometry x="810" y="120" width="250" height="90" as="geometry"/>
        </mxCell>

        <!-- SHARED SERVICES -->
        <mxCell id="shared" value="Shared Services Account — join tooling (no directory)" style="rounded=1;whiteSpace=wrap;html=1;verticalAlign=top;fontStyle=1;fontSize=13;fillColor=#F0ECF5;strokeColor=#6A4D8A;fontColor=#3F2D5A;arcSize=6;" vertex="1" parent="1">
          <mxGeometry x="40" y="340" width="300" height="175" as="geometry"/>
        </mxCell>
        <mxCell id="secrets" value="Secrets Manager — delegated join account" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#FFFFFF;strokeColor=#6A4D8A;fontColor=#3F2D5A;fontSize=11;" vertex="1" parent="1">
          <mxGeometry x="60" y="392" width="260" height="34" as="geometry"/>
        </mxCell>
        <mxCell id="ssmdoc" value="SSM Document — Add-Computer bootstrap" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#FFFFFF;strokeColor=#6A4D8A;fontColor=#3F2D5A;fontSize=11;" vertex="1" parent="1">
          <mxGeometry x="60" y="432" width="260" height="34" as="geometry"/>
        </mxCell>
        <mxCell id="ami" value="Golden Windows AMI + EC2Launch v2" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#FFFFFF;strokeColor=#6A4D8A;fontColor=#3F2D5A;fontSize=11;" vertex="1" parent="1">
          <mxGeometry x="60" y="472" width="260" height="34" as="geometry"/>
        </mxCell>

        <!-- WORKLOAD HEADER -->
        <mxCell id="wlhdr" value="Workload Accounts (per account)" style="text;html=1;fontSize=13;fontStyle=1;align=center;fillColor=none;strokeColor=none;fontColor=#1B2A3A;" vertex="1" parent="1">
          <mxGeometry x="600" y="348" width="200" height="20" as="geometry"/>
        </mxCell>

        <!-- WORKLOAD A -->
        <mxCell id="wlA" value="Workload Account A" style="rounded=1;whiteSpace=wrap;html=1;verticalAlign=top;fontStyle=1;fontSize=12;fillColor=#EAF1F7;strokeColor=#2F5D8A;fontColor=#1B2A3A;arcSize=6;" vertex="1" parent="1">
          <mxGeometry x="410" y="378" width="200" height="165" as="geometry"/>
        </mxCell>
        <mxCell id="ec2A" value="Windows EC2&#10;Add-Computer → corp.example.com&#10;reboot → joined" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#FFFFFF;strokeColor=#2F5D8A;fontColor=#1B2A3A;fontSize=10;" vertex="1" parent="1">
          <mxGeometry x="428" y="412" width="164" height="55" as="geometry"/>
        </mxCell>
        <mxCell id="assocA" value="associate-resolver-rule → VPC" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#FFF7EE;strokeColor=#B5651D;fontColor=#7A4512;fontSize=10;" vertex="1" parent="1">
          <mxGeometry x="428" y="472" width="164" height="30" as="geometry"/>
        </mxCell>
        <mxCell id="tgwA" value="TGW route to DCs (AD ports)" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#EEF3EE;strokeColor=#5A7D5A;fontColor=#33502F;fontSize=9;" vertex="1" parent="1">
          <mxGeometry x="428" y="507" width="164" height="28" as="geometry"/>
        </mxCell>

        <!-- WORKLOAD B -->
        <mxCell id="wlB" value="Workload Account B" style="rounded=1;whiteSpace=wrap;html=1;verticalAlign=top;fontStyle=1;fontSize=12;fillColor=#EAF1F7;strokeColor=#2F5D8A;fontColor=#1B2A3A;arcSize=6;" vertex="1" parent="1">
          <mxGeometry x="630" y="378" width="200" height="165" as="geometry"/>
        </mxCell>
        <mxCell id="ec2B" value="Windows EC2&#10;Add-Computer → corp.example.com&#10;reboot → joined" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#FFFFFF;strokeColor=#2F5D8A;fontColor=#1B2A3A;fontSize=10;" vertex="1" parent="1">
          <mxGeometry x="648" y="412" width="164" height="55" as="geometry"/>
        </mxCell>
        <mxCell id="assocB" value="associate-resolver-rule → VPC" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#FFF7EE;strokeColor=#B5651D;fontColor=#7A4512;fontSize=10;" vertex="1" parent="1">
          <mxGeometry x="648" y="472" width="164" height="30" as="geometry"/>
        </mxCell>
        <mxCell id="tgwB" value="TGW route to DCs (AD ports)" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#EEF3EE;strokeColor=#5A7D5A;fontColor=#33502F;fontSize=9;" vertex="1" parent="1">
          <mxGeometry x="648" y="507" width="164" height="28" as="geometry"/>
        </mxCell>

        <!-- WORKLOAD N -->
        <mxCell id="wlN" value="Workload Account N" style="rounded=1;whiteSpace=wrap;html=1;verticalAlign=top;fontStyle=1;fontSize=12;fillColor=#EAF1F7;strokeColor=#2F5D8A;fontColor=#1B2A3A;arcSize=6;" vertex="1" parent="1">
          <mxGeometry x="850" y="378" width="200" height="165" as="geometry"/>
        </mxCell>
        <mxCell id="ec2N" value="Windows EC2&#10;+ other PHZs (many:many)&#10;no PHZ for corp.example.com" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#FFFFFF;strokeColor=#2F5D8A;fontColor=#1B2A3A;fontSize=10;" vertex="1" parent="1">
          <mxGeometry x="868" y="412" width="164" height="55" as="geometry"/>
        </mxCell>
        <mxCell id="assocN" value="associate-resolver-rule → VPC" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#FFF7EE;strokeColor=#B5651D;fontColor=#7A4512;fontSize=10;" vertex="1" parent="1">
          <mxGeometry x="868" y="472" width="164" height="30" as="geometry"/>
        </mxCell>
        <mxCell id="tgwN" value="TGW route to DCs (AD ports)" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#EEF3EE;strokeColor=#5A7D5A;fontColor=#33502F;fontSize=9;" vertex="1" parent="1">
          <mxGeometry x="868" y="507" width="164" height="28" as="geometry"/>
        </mxCell>

        <!-- EDGES -->
        <!-- DNS forward: outbound endpoint -> DX/TGW -> DCs -->
        <mxCell id="e_dns1" value="DNS fwd" style="endArrow=classic;html=1;strokeColor=#2E7D32;strokeWidth=2;fontColor=#2E7D32;fontStyle=1;" edge="1" parent="1" source="outep" target="dxtgw">
          <mxGeometry relative="1" as="geometry"/>
        </mxCell>
        <mxCell id="e_dns2" style="endArrow=classic;html=1;strokeColor=#2E7D32;strokeWidth=2;" edge="1" parent="1" source="dxtgw" target="dcs">
          <mxGeometry relative="1" as="geometry"/>
        </mxCell>

        <!-- RAM: fwdrule -> ram, ram -> associate cells -->
        <mxCell id="e_ram0" style="endArrow=classic;html=1;dashed=1;strokeColor=#B5651D;strokeWidth=2;" edge="1" parent="1" source="fwdrule" target="ram">
          <mxGeometry relative="1" as="geometry"/>
        </mxCell>
        <mxCell id="e_ramA" style="endArrow=classic;html=1;dashed=1;strokeColor=#B5651D;strokeWidth=1.5;" edge="1" parent="1" source="ram" target="assocA">
          <mxGeometry relative="1" as="geometry"/>
        </mxCell>
        <mxCell id="e_ramB" style="endArrow=classic;html=1;dashed=1;strokeColor=#B5651D;strokeWidth=1.5;" edge="1" parent="1" source="ram" target="assocB">
          <mxGeometry relative="1" as="geometry"/>
        </mxCell>
        <mxCell id="e_ramN" style="endArrow=classic;html=1;dashed=1;strokeColor=#B5651D;strokeWidth=1.5;" edge="1" parent="1" source="ram" target="assocN">
          <mxGeometry relative="1" as="geometry"/>
        </mxCell>

        <!-- Join bootstrap: shared services -> EC2 A -->
        <mxCell id="e_sec" value="creds + SSM doc" style="endArrow=classic;html=1;dashed=1;strokeColor=#6A4D8A;strokeWidth=1.5;fontColor=#6A4D8A;fontStyle=1;" edge="1" parent="1" source="shared" target="ec2A">
          <mxGeometry relative="1" as="geometry"/>
        </mxCell>

        <!-- Join traffic: TGW route cells -> DX/TGW -->
        <mxCell id="e_joinA" value="AD ports" style="endArrow=classic;html=1;strokeColor=#2F5D8A;strokeWidth=1.5;fontColor=#2F5D8A;" edge="1" parent="1" source="tgwA" target="dxtgw">
          <mxGeometry relative="1" as="geometry"/>
        </mxCell>

        <!-- Onprem <-> DX link -->
        <mxCell id="e_link" style="endArrow=classic;startArrow=classic;html=1;strokeColor=#2F5D8A;strokeWidth=2;" edge="1" parent="1" source="dxtgw" target="onprem">
          <mxGeometry relative="1" as="geometry"/>
        </mxCell>

        <!-- LEGEND -->
        <mxCell id="legend" value="Flows &amp; responsibilities:&#10;• DNS (green): EC2 .2 resolver → shared rule → central OUTBOUND endpoint → TGW/DX → on-prem DCs&#10;• RAM (orange dashed): forwarding rule shared to Workloads OU; each account associates the rule to its VPC&#10;• Join bootstrap (purple dashed): EC2 pulls join creds (Secrets Manager) + runs Add-Computer via userdata/SSM&#10;• Join traffic (blue) → TGW → DCs: Kerberos 88, LDAP 389, LDAPS 636, SMB 445, GC 3268/3269, RPC 49152–65535&#10;Ownership: OU delegation, secret rotation, and stale-object cleanup on EC2 termination are yours.&#10;No PHZ for corp.example.com — it would shadow the forwarding rule and break join." style="text;html=1;align=left;verticalAlign=top;fontSize=11;fillColor=#FFFFFF;strokeColor=#D3DBE3;fontColor=#1B2A3A;spacingLeft=10;spacingTop=8;" vertex="1" parent="1">
          <mxGeometry x="40" y="560" width="1020" height="150" as="geometry"/>
        </mxCell>

      </root>
    </mxGraphModel>
  </diagram>
</mxfile>