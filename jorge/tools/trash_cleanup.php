<?
#
# This script purges trash from Jorge database. Run it timely from crontab.
# NOTE: edit settings for your database below
#

print "\n[jorge] Cleaning up trash.......";
$conn=mysql_connect("_YOUR_DATABASE_IP_", "_YOUR_DATABASE_USERNAME_", "_PASSWORD_") or die ("DB connect failed\n");
mysql_select_db ("_YOUR_DATABASE_NAME_") or die ("DB select failed\n");

$xmpp_host="_YOUR_XMPP_HOST"; # Replace dot with underscore f.e.: jabber.org -> jabber_org

$query="select owner_id, peer_name_id,peer_server_id,date as tslice from pending_del where timeframe < date_format((date_sub(curdate(),interval 1 month)), '%Y-%c-%e')";
$result=mysql_query($query);

if (mysql_num_rows($result)>0) {

	$i=0;

	while($row=mysql_fetch_array($result)) {

		$i++;
		$ch_del="delete from `logdb_messages_$row[tslice]"."_$xmpp_host` where owner_id='$row[owner_id]' and peer_name_id='$row[peer_name_id]' and peer_server_id='$row[peer_server_id]' and ext = '1'";
		$li_del="delete from jorge_mylinks where owner_id='$row[owner_id]' and ext='1' and peer_name_id = '$row[peer_name_id]' and peer_server_id='$row[peer_server_id]' and datat = '$row[tslice]'";
		$pe_del="delete from pending_del where owner_id='$row[owner_id]' and peer_name_id = '$row[peer_name_id]' and peer_server_id='$row[peer_server_id]' and date='$row[tslice]'";
		mysql_query("$ch_del") or die("Error #1\n");
		mysql_query("$li_del") or die("Error #2\n");
		mysql_query("$pe_del") or die("Error #3\n");

	}

		print "Deleted $i chats.\n";
	
	}

	else

	{

		print "nothing to delete.\n";

	}

?>
