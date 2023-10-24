

# CNAME ALIAS
```bash
_acme-challenge.xn--80aahqcqybgko.xn--p1ai CNAME  progos.certbot.oooartint.ru
```


# /usr/local/bin/acme.sh --install --home "/etc/acme_sh"

```bash
sudo SL_Key="" acme.sh issue --dns dns_selectel -d xn--80aahqcqybgko.xn--p1ai -d *.xn--80aahqcqybgko.xn--p1ai --domain-alias  progos.certbot.oooartint.ru --home /etc/acme_sh --force
```


#acme.sh --renew

sudo SL_Key="ycnMECEhvtWTfEYaR2CGsxaAV_122723" acme.sh issue --dns dns_selectel -d xn--80aahqcqybgko.xn--p1ai -d *.xn--80aahqcqybgko.xn--p1ai --domain-alias  progos.certbot.oooartint.ru --home /etc/acme_sh --force



#
#/etc/acme_sh/account.conf 
#ACCOUNT_EMAIL='artemsaga@gmail.com'
#DEFAULT_ACME_SERVER='https://acme-v02.api.letsencrypt.org/directory'


