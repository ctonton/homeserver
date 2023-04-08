#!/bin/bash
echo "Setting up Firefox."
if [ $(lsb_release -is) == "Debian" ]
then
  ff=firefox-esr
else
  ff=firefox
fi
apt-get install -y --no-install-recommends ${ff} tigervnc-standalone-server novnc jwm
mkdir /root/Downloads
mkdir /root/.vnc
tee /root/.vnc/xstartup > /dev/null <<EOT
#!/bin/bash
/usr/bin/jwm
EOT
chmod +x /root/.vnc/xstartup
tee /root/.jwmrc > /dev/null <<EOT
<?xml version="1.0"?>
<JWM>
    <Group>
        <Option>maximized</Option>
        <Option>noborder</Option>
    </Group>
    <WindowStyle>
        <Font>Sans-9:bold</Font>
        <Width>4</Width>
        <Height>21</Height>
        <Corner>3</Corner>
        <Foreground>#FFFFFF</Foreground>
        <Background>#555555</Background>
        <Outline>#000000</Outline>
        <Opacity>0.5</Opacity>
        <Active>
            <Foreground>#FFFFFF</Foreground>
            <Background>#0077CC</Background>
            <Outline>#000000</Outline>
            <Opacity>1.0</Opacity>
        </Active>
    </WindowStyle>
    <IconPath>/usr/share/icons</IconPath>
    <IconPath>/usr/share/pixmaps</IconPath>
    <IconPath>/usr/local/share/jwm</IconPath>
    <Desktops width="4" height="1">
        <Background type="solid">#111111</Background>
    </Desktops>
    <DoubleClickSpeed>400</DoubleClickSpeed>
    <DoubleClickDelta>2</DoubleClickDelta>
    <FocusModel>sloppy</FocusModel>
    <SnapMode distance="10">border</SnapMode>
    <MoveMode>opaque</MoveMode>
    <ResizeMode>opaque</ResizeMode>
    <StartupCommand>/root/.ignite.sh</StartupCommand>
</JWM>
EOT
tee /root/.ignite.sh > /dev/null <<'EOT'
#!/bin/bash
websockify -D --web=/usr/share/novnc/ 5800 127.0.0.1:5901
ecode=0
while [ $ecode -eq 0 ]
do
  DISPLAY=:1 firefox
  ecode=$?
done
EOT
chmod +x /root/.ignite.sh
tee /etc/systemd/system/tigervnc.service > /dev/null <<'EOT'
[Unit]
Description=Remote desktop service (VNC)
After=network.target
[Service]
Type=forking
User=root
ExecStart=/usr/bin/tigervncserver -Log *:syslog:0 -localhost no -SecurityTypes None --I-KNOW-THIS-IS-INSECURE :1
ExecStop=/usr/bin/tigervncserver -kill :1
[Install]
WantedBy=multi-user.target
EOT
systemctl enable tigervnc
systemctl start tigervnc
exit
